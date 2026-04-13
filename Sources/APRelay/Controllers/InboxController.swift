import APRelayCore
import Metrics
import Queues
import Tracing
import Vapor

struct InboxController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let signed = routes.grouped(HTTPSignatureVerificationMiddleware())
        signed.post("inbox", use: inbox)
    }

    @Sendable
    private func inbox(req: Request) async throws -> HTTPStatus {
        guard let verifiedActor = req.verifiedActor else {
            throw Abort(.unauthorized, reason: "Signature verification required")
        }

        let body = req.body.data ?? ByteBuffer()
        let activity: APActivity
        do {
            activity = try JSONDecoder().decode(APActivity.self, from: body)
        } catch {
            throw Abort(.badRequest, reason: "Invalid activity JSON: \(error)")
        }

        // Validate that the activity actor's domain matches the verified signer.
        let signerDomain = extractDomain(from: verifiedActor.id)
        let activityActorDomain = extractDomain(from: activity.actor)
        guard let signerDomain, let activityActorDomain,
            signerDomain == activityActorDomain
        else {
            throw Abort(
                .forbidden,
                reason: "Activity actor domain does not match signer domain"
            )
        }

        req.logger.info("Received \(activity.type) from \(activityActorDomain)")

        // Duplicate detection.
        if try await req.activityDeduplicator.isDuplicate(activity.id) {
            req.logger.info("Duplicate activity ignored: \(activity.id)")
            return .accepted
        }

        Counter(
            label: "relay_inbox_activities_total",
            dimensions: [("type", activity.type)]
        ).increment()

        try await withSpan("inbox.process") { span in
            span.attributes["activity.type"] = activity.type
            span.attributes["activity.actor"] = activity.actor
            span.attributes["activity.id"] = activity.id

            let config = req.relayConfig
            let repository = req.repository

            // Check if domain is blocked.
            let actorDomain = extractDomain(from: activity.actor)
            if let domain = actorDomain {
                if try await repository.isBlocked(domain: domain) {
                    throw Abort(.forbidden, reason: "Domain is blocked")
                }

                if config.restrictedMode {
                    if try await !repository.isAllowed(domain: domain) {
                        throw Abort(.forbidden, reason: "Domain is not in allowlist")
                    }
                }
            }

            switch activity.type {
            case "Follow":
                try await handleFollow(
                    activity: activity,
                    verifiedActor: verifiedActor,
                    req: req
                )
            case "Undo":
                try await handleUndo(activity: activity, body: Data(buffer: body), req: req)
            case "Accept":
                try await handleAccept(activity: activity, req: req)
            case "Reject":
                try await handleReject(activity: activity, req: req)
            case "Create", "Announce", "Delete", "Update", "Move", "Add", "Remove":
                try await handleActivity(activity: activity, body: Data(buffer: body), req: req)
            default:
                req.logger.info("Ignoring unsupported activity type: \(activity.type)")
            }
        }

        return .accepted
    }

    // MARK: - Follow

    private func handleFollow(
        activity: APActivity,
        verifiedActor: VerifiedActor,
        req: Request
    ) async throws {
        let config = req.relayConfig
        let repository = req.repository

        guard let object = activity.object,
            case .uri(let objectURI) = object,
            isPublicURI(objectURI) || objectURI == config.actorURL
        else {
            req.logger.info("Follow target is not recognized, ignoring")
            return
        }

        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor
        let inboxURL = verifiedActor.sharedInbox
            ?? verifiedActor.inbox
            ?? guessInboxURL(from: activity.actor)

        let initialState: SubscriberState = config.manualAccept ? .pending : .accepted
        var effectiveState = initialState
        var currentSubscriber: Subscriber?

        if var existing = try await repository.getSubscriber(domain: actorDomain) {
            // If switching from LitePub (relay actor) to Mastodon (public), clean up outbound follow.
            if existing.followObjectURI == config.actorURL && objectURI != config.actorURL {
                try await existing.dispatchUndoFollowIfNeeded(on: req.queue)
                existing.outboundFollowActivityID = nil
            }

            existing.actorID = activity.actor
            existing.inboxURL = inboxURL
            existing.followActivityID = activity.id
            existing.followObjectURI = objectURI
            if existing.state == .rejected {
                existing.state = initialState
            }
            effectiveState = existing.state

            // LitePub: if following relay actor directly and accepted, prepare outbound follow.
            if objectURI == config.actorURL && effectiveState == .accepted
                && existing.outboundFollowActivityID == nil
            {
                existing.outboundFollowActivityID = "\(config.baseURL)/activities/\(UUID().uuidString)"
            }

            try await repository.saveSubscriber(existing)
            currentSubscriber = existing
        } else {
            var subscriber = Subscriber(
                domain: actorDomain,
                inboxURL: inboxURL,
                actorID: activity.actor,
                state: initialState,
                followActivityID: activity.id,
                followObjectURI: objectURI,
                createdAt: Date(),
                updatedAt: Date()
            )

            // LitePub: if following relay actor directly and accepted, prepare outbound follow.
            if objectURI == config.actorURL && initialState == .accepted {
                subscriber.outboundFollowActivityID = "\(config.baseURL)/activities/\(UUID().uuidString)"
            }

            try await repository.saveSubscriber(subscriber)
            currentSubscriber = subscriber
        }

        req.logger.notice("Follow from \(actorDomain), state: \(effectiveState.rawValue)")

        if effectiveState == .accepted {
            try await req.queue.dispatch(
                AcceptJob.self,
                AcceptPayload(
                    inboxURL: inboxURL,
                    followActivityID: activity.id,
                    followerActorID: activity.actor,
                    followObjectURI: objectURI
                ),
                maxRetryCount: 5
            )

            // LitePub: if instance followed the relay actor directly, follow back.
            if objectURI == config.actorURL,
               let outboundFollowID = currentSubscriber?.outboundFollowActivityID
            {
                try await req.queue.dispatch(
                    FollowJob.self,
                    FollowPayload(
                        inboxURL: inboxURL,
                        targetActorID: activity.actor,
                        followActivityID: outboundFollowID
                    ),
                    maxRetryCount: 5
                )
            }

            try await req.queue.dispatch(
                InstanceInfoFetchJob.self,
                InstanceInfoFetchPayload(domain: actorDomain),
                maxRetryCount: 0
            )
        }
    }

    // MARK: - Undo

    private func handleUndo(
        activity: APActivity,
        body: Data,
        req: Request
    ) async throws {
        guard let object = activity.object else { return }

        let innerType: String?
        switch object {
        case .activity(let inner):
            innerType = inner.type
        case .object(let inner):
            innerType = inner.type
        case .uri:
            innerType = "Follow"
        }

        if innerType == "Follow" {
            let actorDomain = extractDomain(from: activity.actor) ?? activity.actor

            if let subscriber = try await req.repository.getSubscriber(domain: actorDomain) {
                // LitePub: if we had an outbound Follow, send Undo Follow back.
                try await subscriber.dispatchUndoFollowIfNeeded(on: req.queue)
                try await req.repository.deleteSubscriber(domain: actorDomain)
                req.logger.notice("Removed subscriber: \(actorDomain)")
            }
        } else {
            try await handleActivity(activity: activity, body: body, req: req)
        }
    }

    // MARK: - Activity (Broadcast)

    private func handleActivity(
        activity: APActivity,
        body: Data,
        req: Request
    ) async throws {
        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor
        let repository = req.repository

        guard
            let subscriber = try await repository.getSubscriber(domain: actorDomain),
            subscriber.state == .accepted
        else {
            req.logger.info("Activity from non-subscriber \(actorDomain), ignoring")
            return
        }

        // Create/Announce are wrapped in a relay-attributed Announce;
        // all other types are forwarded as-is.
        let payload: Data
        switch activity.type {
        case "Create", "Announce":
            let config = req.relayConfig
            let objectURI = activity.object?.uriOrID ?? activity.id

            let announce = APActivity(
                context: .default,
                id: "\(config.baseURL)/activities/\(UUID().uuidString)",
                type: "Announce",
                actor: config.actorURL,
                object: .uri(objectURI),
                to: .single("https://www.w3.org/ns/activitystreams#Public"),
                cc: nil,
                published: ISO8601DateFormatter().string(from: Date())
            )
            payload = try JSONEncoder.apRelay.encode(announce)
        default:
            payload = body
        }

        let inboxURLs = try await repository.getAcceptedInboxURLs()

        let targetInboxes = inboxURLs.filter { $0 != subscriber.inboxURL }
        for inbox in targetInboxes {
            try await req.queue.dispatch(
                DeliveryJob.self,
                DeliveryPayload(activity: payload, inboxURL: inbox),
                maxRetryCount: 5
            )
        }

        req.logger.info(
            "Broadcasting \(activity.type) from \(actorDomain) to \(targetInboxes.count) subscribers"
        )
    }

    // MARK: - Accept (LitePub mutual follow)

    private func handleAccept(activity: APActivity, req: Request) async throws {
        guard let subscriber = try await validateOutboundFollowResponse(activity: activity, req: req)
        else { return }

        let actorDomain = subscriber.domain
        req.logger.notice("Instance \(actorDomain) accepted our Follow (mutual follow established)")
    }

    // MARK: - Reject (LitePub mutual follow)

    private func handleReject(activity: APActivity, req: Request) async throws {
        guard let subscriber = try await validateOutboundFollowResponse(activity: activity, req: req)
        else { return }

        let actorDomain = subscriber.domain
        // Remote already rejected our Follow, so no need to send Undo back.
        try await req.repository.deleteSubscriber(domain: actorDomain)

        req.logger.notice(
            "Instance \(actorDomain) rejected our Follow; removed subscriber"
        )
    }

    /// Validates that an incoming Accept/Reject references our outbound Follow.
    /// Returns the matched subscriber, or nil if validation fails.
    private func validateOutboundFollowResponse(
        activity: APActivity,
        req: Request
    ) async throws -> Subscriber? {
        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor
        let config = req.relayConfig

        guard let subscriber = try await req.repository.getSubscriber(domain: actorDomain),
            let outboundFollowID = subscriber.outboundFollowActivityID
        else {
            req.logger.info(
                "Received \(activity.type) from \(actorDomain) but no outbound Follow tracked, ignoring"
            )
            return nil
        }

        guard subscriber.actorID == activity.actor else {
            req.logger.info(
                "\(activity.type) actor \(activity.actor) does not match subscriber actor \(subscriber.actorID), ignoring"
            )
            return nil
        }

        guard let object = activity.object else {
            req.logger.info("\(activity.type) has no object, ignoring")
            return nil
        }

        switch object {
        case .activity(let inner):
            guard inner.type == "Follow", inner.actor == config.actorURL,
                inner.id == outboundFollowID
            else {
                req.logger.info("\(activity.type) inner activity is not our Follow, ignoring")
                return nil
            }
        case .uri(let uri):
            guard uri == outboundFollowID else {
                req.logger.info("\(activity.type) object URI does not match our Follow, ignoring")
                return nil
            }
        case .object(let obj):
            guard obj.id == outboundFollowID else {
                req.logger.info("\(activity.type) object ID does not match our Follow, ignoring")
                return nil
            }
        }

        return subscriber
    }

    // MARK: - Helpers

    private func extractDomain(from uri: String) -> String? {
        URL(string: uri)?.host()
    }

    private func guessInboxURL(from actorURI: String) -> String {
        guard let url = URL(string: actorURI) else { return actorURI }
        return "\(url.scheme ?? "https")://\(url.host() ?? "")/inbox"
    }

    private func isPublicURI(_ uri: String) -> Bool {
        uri == "https://www.w3.org/ns/activitystreams#Public"
            || uri == "as:Public"
            || uri == "Public"
    }
}

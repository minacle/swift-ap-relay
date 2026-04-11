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

        // Duplicate detection.
        if try await req.activityDeduplicator.isDuplicate(activity.id) {
            req.logger.debug("Duplicate activity ignored: \(activity.id)")
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
                try await handleUndo(activity: activity, req: req)
            case "Create", "Announce":
                try await handleRelay(activity: activity, body: Data(buffer: body), req: req)
            case "Delete", "Update":
                try await handleForward(activity: activity, body: Data(buffer: body), req: req)
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

        let state: SubscriberState = config.manualAccept ? .pending : .accepted

        if var existing = try await repository.getSubscriber(domain: actorDomain) {
            existing.actorID = activity.actor
            existing.inboxURL = inboxURL
            existing.followActivityID = activity.id
            existing.followObjectURI = objectURI
            if existing.state == .rejected {
                existing.state = state
            }
            try await repository.saveSubscriber(existing)
        } else {
            let subscriber = Subscriber(
                domain: actorDomain,
                inboxURL: inboxURL,
                actorID: activity.actor,
                state: state,
                followActivityID: activity.id,
                followObjectURI: objectURI,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await repository.saveSubscriber(subscriber)
        }

        req.logger.info("Follow from \(actorDomain), state: \(state.rawValue)")

        if state == .accepted {
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
        }
    }

    // MARK: - Undo

    private func handleUndo(
        activity: APActivity,
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

        guard innerType == "Follow" else {
            req.logger.info("Undo of non-Follow activity, ignoring")
            return
        }

        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor

        if try await req.repository.getSubscriber(domain: actorDomain) != nil {
            try await req.repository.deleteSubscriber(domain: actorDomain)
            req.logger.info("Removed subscriber: \(actorDomain)")
        }
    }

    // MARK: - Relay (Create/Announce)

    private func handleRelay(
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

        let inboxURLs = try await repository.getAcceptedInboxURLs()

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

        let announceData = try JSONEncoder().encode(announce)

        for inbox in inboxURLs where inbox != subscriber.inboxURL {
            try await req.queue.dispatch(
                DeliveryJob.self,
                DeliveryPayload(activity: announceData, inboxURL: inbox),
                maxRetryCount: 5
            )
        }

        req.logger.info(
            "Relaying \(activity.type) from \(actorDomain) to \(inboxURLs.count - 1) subscribers"
        )
    }

    // MARK: - Forward (Delete/Update)

    private func handleForward(
        activity: APActivity,
        body: Data,
        req: Request
    ) async throws {
        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor
        let repository = req.repository

        guard
            let sender = try await repository.getSubscriber(domain: actorDomain),
            sender.state == .accepted
        else {
            return
        }

        let inboxURLs = try await repository.getAcceptedInboxURLs()

        for inbox in inboxURLs where inbox != sender.inboxURL {
            try await req.queue.dispatch(
                DeliveryJob.self,
                DeliveryPayload(activity: body, inboxURL: inbox),
                maxRetryCount: 5
            )
        }
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

import APRelayCore
import Fluent
import Metrics
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
        if await ActivityDeduplicator.shared.isDuplicate(activity.id) {
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

            // Check if domain is blocked.
            let actorDomain = extractDomain(from: activity.actor)
            if let domain = actorDomain {
                let blocked = try await BlockedDomain.query(on: req.db)
                    .filter(\.$domain == domain)
                    .count()
                if blocked > 0 {
                    throw Abort(.forbidden, reason: "Domain is blocked")
                }

                if config.restrictedMode {
                    let allowed = try await AllowedDomain.query(on: req.db)
                        .filter(\.$domain == domain)
                        .count()
                    if allowed == 0 {
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

        let existing = try await Subscriber.query(on: req.db)
            .filter(\.$domain == actorDomain)
            .first()

        let subscriber: Subscriber
        if let existing {
            existing.actorID = activity.actor
            existing.inboxURL = inboxURL
            existing.followActivityID = activity.id
            existing.followObjectURI = objectURI
            if existing.state == .rejected {
                existing.state = config.manualAccept ? .pending : .accepted
            }
            try await existing.save(on: req.db)
            subscriber = existing
        } else {
            subscriber = Subscriber(
                domain: actorDomain,
                inboxURL: inboxURL,
                actorID: activity.actor,
                state: config.manualAccept ? .pending : .accepted,
                followActivityID: activity.id,
                followObjectURI: objectURI
            )
            try await subscriber.save(on: req.db)
        }

        req.logger.info("Follow from \(actorDomain), state: \(subscriber.state.rawValue)")

        if subscriber.state == .accepted {
            req.deliveryService.enqueueAccept(
                to: inboxURL,
                followActivityID: activity.id,
                followerActorID: activity.actor,
                followObjectURI: objectURI
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
            // A relay only receives Follow activities, so any Undo from a
            // subscriber with a URI-only object is assumed to target a Follow.
            innerType = "Follow"
        }

        guard innerType == "Follow" else {
            req.logger.info("Undo of non-Follow activity, ignoring")
            return
        }

        let actorDomain = extractDomain(from: activity.actor) ?? activity.actor

        if let subscriber = try await Subscriber.query(on: req.db)
            .filter(\.$domain == actorDomain)
            .first()
        {
            try await subscriber.delete(on: req.db)
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

        guard
            let subscriber = try await Subscriber.query(on: req.db)
                .filter(\.$domain == actorDomain)
                .filter(\.$state == .accepted)
                .first()
        else {
            req.logger.info("Activity from non-subscriber \(actorDomain), ignoring")
            return
        }

        let subscribers = try await Subscriber.query(on: req.db)
            .filter(\.$state == .accepted)
            .all()
        let inboxURLs = subscribers.map(\.inboxURL)

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

        req.deliveryService.enqueueBroadcast(
            activity: announceData,
            to: inboxURLs,
            excluding: subscriber.inboxURL
        )

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

        guard
            let sender = try await Subscriber.query(on: req.db)
                .filter(\.$domain == actorDomain)
                .filter(\.$state == .accepted)
                .first()
        else {
            return
        }

        let subscribers = try await Subscriber.query(on: req.db)
            .filter(\.$state == .accepted)
            .all()
        let inboxURLs = subscribers.map(\.inboxURL)

        req.deliveryService.enqueueBroadcast(
            activity: body,
            to: inboxURLs,
            excluding: sender.inboxURL
        )
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

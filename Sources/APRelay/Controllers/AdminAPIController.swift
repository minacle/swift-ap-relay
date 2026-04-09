import Fluent
import Vapor

struct AdminAPIController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.grouped("api", "admin").grouped(AdminAuthMiddleware())
        admin.get("subscribers", use: listSubscribers)
        admin.post("subscribers", ":domain", "accept", use: acceptSubscriber)
        admin.post("subscribers", ":domain", "reject", use: rejectSubscriber)
        admin.delete("subscribers", ":domain", use: removeSubscriber)
        admin.get("blocked-domains", use: listBlockedDomains)
        admin.post("blocked-domains", use: blockDomain)
        admin.delete("blocked-domains", ":domain", use: unblockDomain)
    }

    // MARK: - Subscribers

    @Sendable
    private func listSubscribers(req: Request) async throws -> [Subscriber.DTO] {
        let stateFilter = req.query[String.self, at: "state"]
        var query = Subscriber.query(on: req.db)
        if let stateFilter, let state = SubscriberState(rawValue: stateFilter) {
            query = query.filter(\.$state == state)
        }
        return try await query.all().map(\.toDTO)
    }

    @Sendable
    private func acceptSubscriber(req: Request) async throws -> AdminResponse {
        let domain = req.parameters.get("domain")!

        guard
            let subscriber = try await Subscriber.query(on: req.db)
                .filter(\.$domain == domain)
                .first()
        else {
            throw Abort(.notFound, reason: "Subscriber not found")
        }

        subscriber.state = .accepted
        try await subscriber.save(on: req.db)

        Task {
            try await req.deliveryService.sendAccept(
                to: subscriber.inboxURL,
                followActivityID: subscriber.followActivityID,
                followerActorID: subscriber.actorID,
                followObjectURI: subscriber.followObjectURI
            )
        }

        return AdminResponse(status: "accepted", domain: domain)
    }

    @Sendable
    private func rejectSubscriber(req: Request) async throws -> AdminResponse {
        let domain = req.parameters.get("domain")!

        guard
            let subscriber = try await Subscriber.query(on: req.db)
                .filter(\.$domain == domain)
                .first()
        else {
            throw Abort(.notFound, reason: "Subscriber not found")
        }

        subscriber.state = .rejected
        try await subscriber.save(on: req.db)

        Task {
            try await req.deliveryService.sendReject(
                to: subscriber.inboxURL,
                followActivityID: subscriber.followActivityID,
                followerActorID: subscriber.actorID,
                followObjectURI: subscriber.followObjectURI
            )
        }

        return AdminResponse(status: "rejected", domain: domain)
    }

    @Sendable
    private func removeSubscriber(req: Request) async throws -> AdminResponse {
        let domain = req.parameters.get("domain")!

        guard
            let subscriber = try await Subscriber.query(on: req.db)
                .filter(\.$domain == domain)
                .first()
        else {
            throw Abort(.notFound, reason: "Subscriber not found")
        }

        try await subscriber.delete(on: req.db)
        return AdminResponse(status: "removed", domain: domain)
    }

    // MARK: - Blocked Domains

    @Sendable
    private func listBlockedDomains(req: Request) async throws -> [BlockedDomain.DTO] {
        try await BlockedDomain.query(on: req.db).all().map(\.toDTO)
    }

    @Sendable
    private func blockDomain(req: Request) async throws -> AdminResponse {
        let body = try req.content.decode(BlockRequest.self)

        let existing = try await BlockedDomain.query(on: req.db)
            .filter(\.$domain == body.domain)
            .first()

        if existing != nil {
            throw Abort(.conflict, reason: "Domain already blocked")
        }

        let blocked = BlockedDomain(domain: body.domain, reason: body.reason)
        try await blocked.save(on: req.db)

        if let subscriber = try await Subscriber.query(on: req.db)
            .filter(\.$domain == body.domain)
            .first()
        {
            try await subscriber.delete(on: req.db)
        }

        return AdminResponse(status: "blocked", domain: body.domain)
    }

    @Sendable
    private func unblockDomain(req: Request) async throws -> AdminResponse {
        let domain = req.parameters.get("domain")!

        guard
            let blocked = try await BlockedDomain.query(on: req.db)
                .filter(\.$domain == domain)
                .first()
        else {
            throw Abort(.notFound, reason: "Domain not blocked")
        }

        try await blocked.delete(on: req.db)
        return AdminResponse(status: "unblocked", domain: domain)
    }
}

// MARK: - Request/Response DTOs

struct BlockRequest: Content {
    let domain: String
    let reason: String?
}

struct AdminResponse: Content {
    let status: String
    let domain: String
}

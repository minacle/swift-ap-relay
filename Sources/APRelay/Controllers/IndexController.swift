import Vapor

struct IndexController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: index)
    }

    @Sendable
    private func index(req: Request) async throws -> View {
        let config = req.relayConfig

        let subscribers = try await req.repository.getAllSubscribers(state: .accepted)

        let context = IndexContext(
            domain: config.domain,
            inboxURL: config.inboxURL,
            actorURL: config.actorURL,
            description: config.relayDescription,
            hasDescription: !config.relayDescription.isEmpty,
            footer: config.relayFooter,
            hasFooter: !config.relayFooter.isEmpty,
            subscribers: subscribers.map { SubscriberItem(domain: $0.domain) },
            subscriberCount: subscribers.count
        )

        return try await req.view.render("index", context)
    }
}

private struct IndexContext: Encodable {
    let domain: String
    let inboxURL: String
    let actorURL: String
    let description: String
    let hasDescription: Bool
    let footer: String
    let hasFooter: Bool
    let subscribers: [SubscriberItem]
    let subscriberCount: Int
}

private struct SubscriberItem: Encodable {
    let domain: String
}

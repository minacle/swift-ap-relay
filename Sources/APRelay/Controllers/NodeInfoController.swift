import JSON
import Vapor

struct NodeInfoController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped(".well-known").get("nodeinfo", use: wellKnown)
        routes.get("nodeinfo", "2.1", use: nodeInfo)
    }

    @Sendable
    private func wellKnown(req: Request) async throws -> NodeInfoWellKnown {
        let config = req.relayConfig
        return NodeInfoWellKnown(
            links: [
                NodeInfoLink(
                    rel: "http://nodeinfo.diaspora.software/ns/schema/2.1",
                    href: "\(config.baseURL)/nodeinfo/2.1"
                ),
            ]
        )
    }

    @Sendable
    private func nodeInfo(req: Request) async throws -> NodeInfoResponse {
        let config = req.relayConfig
        let subscribers = try await req.repository.getAllSubscribers(state: .accepted)
        let peers = subscribers.map(\.domain)

        return NodeInfoResponse(
            version: "2.1",
            software: NodeInfoSoftware(
                name: "ap-relay",
                version: AppInfo.version,
                repository: "https://github.com/sinoru/swift-ap-relay"
            ),
            protocols: ["activitypub"],
            services: NodeInfoServices(inbound: [], outbound: []),
            usage: NodeInfoUsage(
                users: NodeInfoUsers(total: 0, activeMonth: 0, activeHalfyear: 0),
                localPosts: 0
            ),
            openRegistrations: !config.restrictedMode,
            metadata: ["peers": .array(peers.map { .string($0) })]
        )
    }
}

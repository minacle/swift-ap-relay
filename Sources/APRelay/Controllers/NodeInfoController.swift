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
                name: "aprelay",
                version: AppInfo.version,
                repository: "https://github.com/sinoru/swift-ap-relay"
            ),
            protocols: ["activitypub"],
            usage: NodeInfoUsage(
                users: NodeInfoUsers(total: 0, activeMonth: 0, activeHalfyear: 0),
                localPosts: 0
            ),
            openRegistrations: !config.restrictedMode,
            metadata: NodeInfoMetadata(peers: peers)
        )
    }
}

// MARK: - Response Types

struct NodeInfoWellKnown: Content {
    let links: [NodeInfoLink]
}

struct NodeInfoLink: Codable, Sendable {
    let rel: String
    let href: String
}

struct NodeInfoResponse: Content {
    let version: String
    let software: NodeInfoSoftware
    let protocols: [String]
    let usage: NodeInfoUsage
    let openRegistrations: Bool
    let metadata: NodeInfoMetadata
}

struct NodeInfoSoftware: Codable, Sendable {
    let name: String
    let version: String
    let repository: String
}

struct NodeInfoUsage: Codable, Sendable {
    let users: NodeInfoUsers
    let localPosts: Int
}

struct NodeInfoUsers: Codable, Sendable {
    let total: Int
    let activeMonth: Int
    let activeHalfyear: Int
}

struct NodeInfoMetadata: Codable, Sendable {
    let peers: [String]
}

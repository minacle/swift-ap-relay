import JSON
import Vapor

// MARK: - Well-Known Discovery

struct NodeInfoWellKnown: Content {
    let links: [NodeInfoLink]
}

struct NodeInfoLink: Codable, Sendable {
    let rel: String
    let href: String
}

// MARK: - NodeInfo 2.x Document

struct NodeInfoResponse: Content {
    let version: String
    let software: NodeInfoSoftware
    let protocols: [String]
    let services: NodeInfoServices
    let usage: NodeInfoUsage
    let openRegistrations: Bool
    let metadata: JSON.Value

    init(
        version: String,
        software: NodeInfoSoftware,
        protocols: [String],
        services: NodeInfoServices,
        usage: NodeInfoUsage,
        openRegistrations: Bool,
        metadata: JSON.Value
    ) {
        self.version = version
        self.software = software
        self.protocols = protocols
        self.services = services
        self.usage = usage
        self.openRegistrations = openRegistrations
        self.metadata = metadata
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        software = try container.decode(NodeInfoSoftware.self, forKey: .software)
        protocols = try container.decode([String].self, forKey: .protocols)
        services = try container.decodeIfPresent(NodeInfoServices.self, forKey: .services)
            ?? NodeInfoServices(inbound: [], outbound: [])
        usage = try container.decode(NodeInfoUsage.self, forKey: .usage)
        openRegistrations = try container.decodeIfPresent(Bool.self, forKey: .openRegistrations) ?? false
        metadata = try container.decodeIfPresent(JSON.Value.self, forKey: .metadata) ?? [:]
    }
}

struct NodeInfoSoftware: Codable, Sendable {
    let name: String
    let version: String
    let repository: String?
}

struct NodeInfoServices: Codable, Sendable {
    let inbound: [String]
    let outbound: [String]
}

struct NodeInfoUsage: Codable, Sendable {
    let users: NodeInfoUsers
    let localPosts: Int?
}

struct NodeInfoUsers: Codable, Sendable {
    let total: Int?
    let activeMonth: Int?
    let activeHalfyear: Int?
}

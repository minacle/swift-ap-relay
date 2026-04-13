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
    let usage: NodeInfoUsage
    let openRegistrations: Bool?
    let metadata: NodeInfoMetadata?
}

struct NodeInfoSoftware: Codable, Sendable {
    let name: String
    let version: String
    let repository: String?
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

struct NodeInfoMetadata: Codable, Sendable {
    let peers: [String]?
    let staffAccounts: [String]?
}

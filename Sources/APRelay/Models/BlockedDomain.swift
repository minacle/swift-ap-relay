import Vapor

struct BlockedDomain: Codable, Content, Sendable {
    let domain: String
    let reason: String?
    let createdAt: Date?
}

import Fluent
import Vapor

final class BlockedDomain: Model, @unchecked Sendable {
    static let schema = "blocked_domains"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "domain")
    var domain: String

    @OptionalField(key: "reason")
    var reason: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, domain: String, reason: String? = nil) {
        self.id = id
        self.domain = domain
        self.reason = reason
    }

    /// Data Transfer Object for API responses.
    struct DTO: Content {
        let domain: String
        let reason: String?
        let createdAt: Date?
    }

    var toDTO: DTO {
        DTO(domain: domain, reason: reason, createdAt: createdAt)
    }
}

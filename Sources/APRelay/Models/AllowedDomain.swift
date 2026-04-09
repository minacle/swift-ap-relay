import Fluent
import Vapor

final class AllowedDomain: Model, Content, @unchecked Sendable {
    static let schema = "allowed_domains"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "domain")
    var domain: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, domain: String) {
        self.id = id
        self.domain = domain
    }
}

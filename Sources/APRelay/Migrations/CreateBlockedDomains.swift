import Fluent

struct CreateBlockedDomains: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("blocked_domains")
            .id()
            .field("domain", .string, .required)
            .field("reason", .string)
            .field("created_at", .datetime)
            .unique(on: "domain")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("blocked_domains").delete()
    }
}

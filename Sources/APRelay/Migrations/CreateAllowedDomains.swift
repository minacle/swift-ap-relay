import Fluent

struct CreateAllowedDomains: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("allowed_domains")
            .id()
            .field("domain", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "domain")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("allowed_domains").delete()
    }
}

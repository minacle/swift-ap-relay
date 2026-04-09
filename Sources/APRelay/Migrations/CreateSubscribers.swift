import Fluent

struct CreateSubscribers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("subscribers")
            .id()
            .field("domain", .string, .required)
            .field("inbox_url", .string, .required)
            .field("actor_id", .string, .required)
            .field("state", .string, .required)
            .field("follow_activity_id", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "domain")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("subscribers").delete()
    }
}

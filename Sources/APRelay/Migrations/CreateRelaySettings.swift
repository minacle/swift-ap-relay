import Fluent

struct CreateRelaySettings: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("relay_settings")
            .id()
            .field("key", .string, .required)
            .field("value", .string, .required)
            .unique(on: "key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("relay_settings").delete()
    }
}

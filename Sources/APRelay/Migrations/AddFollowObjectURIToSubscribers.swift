import Fluent

struct AddFollowObjectURIToSubscribers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("subscribers")
            .field("follow_object_uri", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("subscribers")
            .deleteField("follow_object_uri")
            .update()
    }
}

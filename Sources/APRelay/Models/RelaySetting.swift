import Fluent
import Vapor

final class RelaySetting: Model, @unchecked Sendable {
    static let schema = "relay_settings"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "key")
    var key: String

    @Field(key: "value")
    var value: String

    init() {}

    init(id: UUID? = nil, key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }

    static func get(key: String, on db: Database) async throws -> String? {
        try await RelaySetting.query(on: db)
            .filter(\.$key == key)
            .first()?
            .value
    }

    static func set(key: String, value: String, on db: Database) async throws {
        if let existing = try await RelaySetting.query(on: db)
            .filter(\.$key == key)
            .first()
        {
            existing.value = value
            try await existing.save(on: db)
        } else {
            let setting = RelaySetting(key: key, value: value)
            try await setting.save(on: db)
        }
    }
}

import Fluent
import Vapor

enum SubscriberState: String, Codable, Sendable {
    case pending
    case accepted
    case rejected
}

final class Subscriber: Model, @unchecked Sendable {
    static let schema = "subscribers"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "domain")
    var domain: String

    @Field(key: "inbox_url")
    var inboxURL: String

    @Field(key: "actor_id")
    var actorID: String

    @Field(key: "state")
    var state: SubscriberState

    @Field(key: "follow_activity_id")
    var followActivityID: String

    @OptionalField(key: "follow_object_uri")
    var followObjectURI: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        domain: String,
        inboxURL: String,
        actorID: String,
        state: SubscriberState,
        followActivityID: String,
        followObjectURI: String? = nil
    ) {
        self.id = id
        self.domain = domain
        self.inboxURL = inboxURL
        self.actorID = actorID
        self.state = state
        self.followActivityID = followActivityID
        self.followObjectURI = followObjectURI
    }

    /// Data Transfer Object for API responses.
    struct DTO: Content {
        let domain: String
        let inboxURL: String
        let actorID: String
        let state: SubscriberState
        let followObjectURI: String?
        let createdAt: Date?
        let updatedAt: Date?
    }

    var toDTO: DTO {
        DTO(
            domain: domain,
            inboxURL: inboxURL,
            actorID: actorID,
            state: state,
            followObjectURI: followObjectURI,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

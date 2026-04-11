import Foundation

/// A flexible ActivityPub activity representation.
package struct APActivity: Codable, Sendable {
    package let context: APContext?
    package let id: String
    package let type: String
    package let actor: String
    package let object: APObject?
    package let to: APStringOrArray?
    package let cc: APStringOrArray?
    package let published: String?

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case id
        case type
        case actor
        case object
        case to
        case cc
        case published
    }

    package init(
        context: APContext?,
        id: String,
        type: String,
        actor: String,
        object: APObject?,
        to: APStringOrArray?,
        cc: APStringOrArray?,
        published: String?
    ) {
        self.context = context
        self.id = id
        self.type = type
        self.actor = actor
        self.object = object
        self.to = to
        self.cc = cc
        self.published = published
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decodeIfPresent(APContext.self, forKey: .context)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        object = try container.decodeIfPresent(APObject.self, forKey: .object)
        to = try container.decodeIfPresent(APStringOrArray.self, forKey: .to)
        cc = try container.decodeIfPresent(APStringOrArray.self, forKey: .cc)
        published = try container.decodeIfPresent(String.self, forKey: .published)

        // actor can be a string or an object with an "id" field.
        if let actorString = try? container.decode(String.self, forKey: .actor) {
            actor = actorString
        } else {
            let actorObj = try container.decode(APActorRef.self, forKey: .actor)
            actor = actorObj.id
        }
    }
}

/// Minimal actor reference used when `actor` is sent as an object.
private struct APActorRef: Decodable {
    let id: String
}

/// An ActivityPub object that can be either a URI string or a full object.
package indirect enum APObject: Codable, Sendable {
    case uri(String)
    case activity(APActivity)
    case object(APGenericObject)

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .uri(let uri):
            try container.encode(uri)
        case .activity(let activity):
            try container.encode(activity)
        case .object(let obj):
            try container.encode(obj)
        }
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let uri = try? container.decode(String.self) {
            self = .uri(uri)
        } else if let activity = try? container.decode(APActivity.self) {
            self = .activity(activity)
        } else {
            let obj = try container.decode(APGenericObject.self)
            self = .object(obj)
        }
    }

    /// Returns the URI string if this is a URI, or the `id` if it's an object.
    package var uriOrID: String? {
        switch self {
        case .uri(let uri): uri
        case .activity(let activity): activity.id
        case .object(let obj): obj.id
        }
    }
}

/// A generic ActivityPub object with common fields.
package struct APGenericObject: Codable, Sendable {
    package let id: String?
    package let type: String?
    package let actor: String?
    package let content: String?
    package let attributedTo: String?
}

/// A value that can be a single string or an array of strings (common in ActivityPub).
package enum APStringOrArray: Codable, Sendable {
    case single(String)
    case array([String])

    package var values: [String] {
        switch self {
        case .single(let value): [value]
        case .array(let values): values
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        }
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
        } else {
            let values = try container.decode([String].self)
            self = .array(values)
        }
    }

    /// Whether this contains the ActivityPub Public collection URI.
    package var isPublic: Bool {
        values.contains("https://www.w3.org/ns/activitystreams#Public")
            || values.contains("as:Public")
            || values.contains("Public")
    }
}

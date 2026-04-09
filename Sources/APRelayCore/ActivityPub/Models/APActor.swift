import Foundation

/// ActivityPub Actor representation for the relay.
public struct APActor: Codable, Sendable {
    public let context: APContext
    public let id: String
    public let type: String
    public let preferredUsername: String
    public let name: String
    public let summary: String
    public let inbox: String
    public let url: String
    public let publicKey: APPublicKey

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case id
        case type
        case preferredUsername
        case name
        case summary
        case inbox
        case url
        case publicKey
    }

    public init(
        context: APContext,
        id: String,
        type: String,
        preferredUsername: String,
        name: String,
        summary: String,
        inbox: String,
        url: String,
        publicKey: APPublicKey
    ) {
        self.context = context
        self.id = id
        self.type = type
        self.preferredUsername = preferredUsername
        self.name = name
        self.summary = summary
        self.inbox = inbox
        self.url = url
        self.publicKey = publicKey
    }
}

/// Remote actor fetched for signature verification.
public struct RemoteActor: Codable, Sendable {
    public let id: String
    public let type: String?
    public let inbox: String?
    public let endpoints: RemoteActorEndpoints?
    public let publicKey: APPublicKey?

    public init(
        id: String,
        type: String?,
        inbox: String?,
        endpoints: RemoteActorEndpoints?,
        publicKey: APPublicKey?
    ) {
        self.id = id
        self.type = type
        self.inbox = inbox
        self.endpoints = endpoints
        self.publicKey = publicKey
    }

    /// The shared inbox URL, if available.
    public var sharedInbox: String? {
        endpoints?.sharedInbox
    }
}

/// Endpoints block from a remote actor document.
public struct RemoteActorEndpoints: Codable, Sendable {
    public let sharedInbox: String?

    public init(sharedInbox: String?) {
        self.sharedInbox = sharedInbox
    }
}

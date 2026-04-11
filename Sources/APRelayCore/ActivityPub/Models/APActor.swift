import Foundation

/// ActivityPub Actor representation for the relay.
package struct APActor: Codable, Sendable {
    package let context: APContext
    package let id: String
    package let type: String
    package let preferredUsername: String
    package let name: String
    package let summary: String
    package let inbox: String
    package let url: String
    package let publicKey: APPublicKey

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

    package init(
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
package struct RemoteActor: Codable, Sendable {
    package let id: String
    package let type: String?
    package let inbox: String?
    package let endpoints: RemoteActorEndpoints?
    package let publicKey: APPublicKey?

    package init(
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
    package var sharedInbox: String? {
        endpoints?.sharedInbox
    }
}

/// Endpoints block from a remote actor document.
package struct RemoteActorEndpoints: Codable, Sendable {
    package let sharedInbox: String?

    package init(sharedInbox: String?) {
        self.sharedInbox = sharedInbox
    }
}

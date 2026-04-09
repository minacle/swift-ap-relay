import Foundation

/// ActivityPub public key block embedded in an actor document.
public struct APPublicKey: Codable, Sendable {
    public let id: String
    public let owner: String
    public let publicKeyPem: String

    public init(id: String, owner: String, publicKeyPem: String) {
        self.id = id
        self.owner = owner
        self.publicKeyPem = publicKeyPem
    }
}

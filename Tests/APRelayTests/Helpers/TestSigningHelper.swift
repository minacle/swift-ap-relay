import APRelayCore
import Crypto
import _CryptoExtras
import Foundation
import Vapor

/// Utilities for generating signed HTTP requests in tests.
enum TestSigning {
    static let privateKey = try! _RSA.Signing.PrivateKey(keySize: .bits2048)
    static var publicKeyPEM: String { privateKey.publicKey.pemRepresentation }
    static let httpSignature = HTTPSignature()

    static let testActorID = "https://remote.example/actor"
    static let testActorDomain = "remote.example"
    static let testInboxURL = "https://remote.example/inbox"
    static let testSharedInboxURL = "https://remote.example/inbox"

    /// Signs a request body and returns the headers to include.
    static func signedHeaders(
        path: String = "/inbox",
        host: String = "localhost",
        body: Data,
        keyID: String = "\(testActorID)#main-key"
    ) throws -> [String: String] {
        try httpSignature.sign(
            method: "post",
            path: path,
            host: host,
            body: body,
            privateKey: privateKey,
            keyID: keyID
        )
    }

    /// Creates a Follow activity (Mastodon style: object = public collection).
    static func makeFollowActivity(
        id: String = "https://remote.example/activities/\(UUID().uuidString)",
        actor: String = testActorID,
        objectURI: String = "https://www.w3.org/ns/activitystreams#Public"
    ) -> APActivity {
        APActivity(
            context: .default,
            id: id,
            type: "Follow",
            actor: actor,
            object: .uri(objectURI),
            to: nil,
            cc: nil,
            published: nil
        )
    }

    /// Creates an Undo activity wrapping a Follow.
    static func makeUndoActivity(
        id: String = "https://remote.example/activities/\(UUID().uuidString)",
        actor: String = testActorID,
        followID: String = "https://remote.example/activities/follow-1",
        objectAsURI: Bool = false
    ) -> APActivity {
        let object: APObject
        if objectAsURI {
            object = .uri(followID)
        } else {
            object = .activity(APActivity(
                context: nil,
                id: followID,
                type: "Follow",
                actor: actor,
                object: .uri("https://www.w3.org/ns/activitystreams#Public"),
                to: nil,
                cc: nil,
                published: nil
            ))
        }
        return APActivity(
            context: .default,
            id: id,
            type: "Undo",
            actor: actor,
            object: object,
            to: nil,
            cc: nil,
            published: nil
        )
    }

    /// Creates a Create activity.
    static func makeCreateActivity(
        id: String = "https://remote.example/activities/\(UUID().uuidString)",
        actor: String = testActorID
    ) -> APActivity {
        APActivity(
            context: .default,
            id: id,
            type: "Create",
            actor: actor,
            object: .uri("https://remote.example/notes/\(UUID().uuidString)"),
            to: .single("https://www.w3.org/ns/activitystreams#Public"),
            cc: nil,
            published: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Creates a Delete activity.
    static func makeDeleteActivity(
        id: String = "https://remote.example/activities/\(UUID().uuidString)",
        actor: String = testActorID
    ) -> APActivity {
        APActivity(
            context: .default,
            id: id,
            type: "Delete",
            actor: actor,
            object: .uri("https://remote.example/notes/\(UUID().uuidString)"),
            to: .single("https://www.w3.org/ns/activitystreams#Public"),
            cc: nil,
            published: nil
        )
    }

    /// Encodes an activity and returns the signed (headers, body) pair.
    static func signedRequest(
        activity: APActivity,
        path: String = "/inbox",
        host: String = "localhost"
    ) throws -> (headers: HTTPHeaders, body: ByteBuffer) {
        let data = try JSONEncoder().encode(activity)
        let sigHeaders = try signedHeaders(path: path, host: host, body: data)
        var headers = HTTPHeaders()
        for (name, value) in sigHeaders {
            headers.add(name: name, value: value)
        }
        return (headers, ByteBuffer(data: data))
    }
}

import APRelayCore
import Vapor
@testable import APRelay

/// Mock actor fetcher that returns a pre-configured remote actor for tests.
struct MockActorFetcher: ActorFetcher {
    let remoteActor: RemoteActor

    init(
        id: String = TestSigning.testActorID,
        inbox: String = TestSigning.testInboxURL,
        sharedInbox: String? = TestSigning.testSharedInboxURL,
        publicKeyPEM: String = TestSigning.publicKeyPEM
    ) {
        let endpoints: RemoteActorEndpoints?
        if let sharedInbox {
            endpoints = RemoteActorEndpoints(sharedInbox: sharedInbox)
        } else {
            endpoints = nil
        }
        self.remoteActor = RemoteActor(
            id: id,
            type: "Application",
            inbox: inbox,
            endpoints: endpoints,
            publicKey: APPublicKey(
                id: "\(id)#main-key",
                owner: id,
                publicKeyPem: publicKeyPEM
            )
        )
    }

    func fetchActor(url: String, client: Client) async throws -> RemoteActor {
        remoteActor
    }
}

/// Mock actor fetcher that always fails (for testing fetch failures).
struct FailingActorFetcher: ActorFetcher {
    func fetchActor(url: String, client: Client) async throws -> RemoteActor {
        throw Abort(.badGateway, reason: "Mock: remote actor fetch failed")
    }
}

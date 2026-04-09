import APRelayCore
import Vapor

struct ActorController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("actor", use: actor)
    }

    @Sendable
    private func actor(req: Request) async throws -> ActivityJSON<APActor> {
        let config = req.relayConfig
        let keyManager = KeyManager(db: req.db)
        let publicKeyPEM = try await keyManager.getPublicKeyPEM()

        return ActivityJSON(APActor(
            context: .default,
            id: config.actorURL,
            type: "Application",
            preferredUsername: "relay",
            name: "AP Relay",
            summary: "ActivityPub Relay Server",
            inbox: config.inboxURL,
            url: config.actorURL,
            publicKey: APPublicKey(
                id: "\(config.actorURL)#main-key",
                owner: config.actorURL,
                publicKeyPem: publicKeyPEM
            )
        ))
    }
}

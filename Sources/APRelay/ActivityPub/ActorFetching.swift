import APRelayCore
import Vapor

/// Protocol for fetching remote ActivityPub actor documents.
protocol ActorFetcher: Sendable {
    func fetchActor(url: String, client: Client) async throws -> RemoteActor
}

/// Default implementation that fetches actors via HTTP.
struct HTTPActorFetcher: ActorFetcher {
    func fetchActor(url: String, client: Client) async throws -> RemoteActor {
        let uri = URI(string: url)
        let response = try await client.get(uri) { req in
            req.headers.add(name: "Accept", value: "application/activity+json")
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to fetch remote actor: \(url)")
        }
        return try response.content.decode(RemoteActor.self, using: JSONDecoder())
    }
}

// MARK: - App Storage

private struct ActorFetcherKey: StorageKey {
    typealias Value = any ActorFetcher
}

extension Application {
    var actorFetcher: any ActorFetcher {
        get {
            storage[ActorFetcherKey.self] ?? HTTPActorFetcher()
        }
        set {
            storage[ActorFetcherKey.self] = newValue
        }
    }
}

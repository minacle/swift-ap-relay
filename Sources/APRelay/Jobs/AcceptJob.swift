import APRelayCore
import Foundation
import Queues
import Vapor

/// Payload for sending an Accept activity in response to a Follow.
struct AcceptPayload: Codable, Sendable {
    let inboxURL: String
    let followActivityID: String
    let followerActorID: String
    let followObjectURI: String?
}

/// Sends a signed Accept activity to a remote inbox.
struct AcceptJob: AsyncJob {
    typealias Payload = AcceptPayload

    func dequeue(_ context: QueueContext, _ payload: AcceptPayload) async throws {
        let app = context.application
        let config = app.relayConfig
        let privateKey = app.signingKey

        let objectURI = payload.followObjectURI
            ?? "https://www.w3.org/ns/activitystreams#Public"

        let accept = APActivity(
            context: .default,
            id: "\(config.baseURL)/activities/\(UUID().uuidString)",
            type: "Accept",
            actor: config.actorURL,
            object: .activity(APActivity(
                context: nil,
                id: payload.followActivityID,
                type: "Follow",
                actor: payload.followerActorID,
                object: .uri(objectURI),
                to: nil,
                cc: nil,
                published: nil
            )),
            to: .single(payload.followerActorID),
            cc: nil,
            published: ISO8601DateFormatter().string(from: Date())
        )

        let data = try JSONEncoder().encode(accept)

        try await SignedDeliveryHelper.send(
            activity: data,
            to: payload.inboxURL,
            config: config,
            privateKey: privateKey,
            client: app.client,
            logger: context.logger
        )

        context.logger.info("Sent Accept to \(payload.inboxURL)")
    }

    func error(_ context: QueueContext, _ error: any Error, _ payload: AcceptPayload) async throws {
        context.logger.error("Failed to send Accept to \(payload.inboxURL): \(error)")
    }
}

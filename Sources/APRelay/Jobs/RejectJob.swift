import APRelayCore
import Foundation
import Queues
import Vapor

/// Payload for sending a Reject activity in response to a Follow.
struct RejectPayload: Codable, Sendable {
    let inboxURL: String
    let followActivityID: String
    let followerActorID: String
    let followObjectURI: String?
}

/// Sends a signed Reject activity to a remote inbox.
struct RejectJob: AsyncJob {
    typealias Payload = RejectPayload

    func dequeue(_ context: QueueContext, _ payload: RejectPayload) async throws {
        let app = context.application
        let config = app.relayConfig
        let privateKey = app.signingKey

        let objectURI = payload.followObjectURI
            ?? "https://www.w3.org/ns/activitystreams#Public"

        let reject = APActivity(
            context: .default,
            id: "\(config.baseURL)/activities/\(UUID().uuidString)",
            type: "Reject",
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

        let data = try JSONEncoder.apRelay.encode(reject)

        try await SignedDeliveryHelper.send(
            activity: data,
            to: payload.inboxURL,
            config: config,
            privateKey: privateKey,
            client: app.client,
            logger: context.logger
        )

        context.logger.notice("Sent Reject to \(payload.inboxURL)")
    }

    func error(_ context: QueueContext, _ error: any Error, _ payload: RejectPayload) async throws {
        context.logger.error("Failed to send Reject to \(payload.inboxURL): \(error)")
    }
}

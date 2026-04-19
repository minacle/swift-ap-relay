import Foundation
import Metrics
import Queues
import Tracing
import Vapor

/// Payload for delivering a pre-encoded activity to a single inbox.
struct DeliveryPayload: Codable, Sendable {
    let activity: Data
    let inboxURL: String
}

/// Delivers a signed ActivityPub activity to a single remote inbox.
///
/// Each inbox in a broadcast gets its own `DeliveryJob`, so queue `workerCount`
/// naturally limits concurrency.
struct DeliveryJob: AsyncJob {
    typealias Payload = DeliveryPayload

    func dequeue(_ context: QueueContext, _ payload: DeliveryPayload) async throws {
        let app = context.application
        let config = app.relayConfig
        let privateKey = app.signingKey

        try await withSpan("delivery.send") { span in
            span.attributes["delivery.inbox"] = payload.inboxURL

            try await SignedDeliveryHelper.send(
                activity: payload.activity,
                to: payload.inboxURL,
                config: config,
                privateKey: privateKey,
                client: app.client,
                logger: context.logger
            )
        }

        Counter(
            label: "relay_delivery_total",
            dimensions: [("result", "success")]
        ).increment()
        context.logger.info("Delivered to \(payload.inboxURL)")
    }

    func error(_ context: QueueContext, _ error: any Error, _ payload: DeliveryPayload) async throws {
        context.logger.warning("Delivery failed for \(payload.inboxURL): \(error)")
        Counter(
            label: "relay_delivery_total",
            dimensions: [("result", "failure")]
        ).increment()
    }

    func nextRetryIn(attempt: Int) -> Int {
        Self.exponentialBackoffSeconds(attempt: attempt, base: 60, maxInterval: 30 * 60)
    }
}

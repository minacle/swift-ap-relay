import APRelayCore
import Queues
import Vapor

/// Periodically dispatches ``NodeInfoFetchJob`` for each accepted subscriber.
///
/// The actual HTTP fetching happens in individual queue jobs, so worker count
/// naturally limits concurrent outbound requests.
struct NodeInfoCheckJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let app = context.application
        let subscribers = try await app.repository.getAllSubscribers(state: .accepted)
        guard !subscribers.isEmpty else { return }

        for subscriber in subscribers {
            try await app.queues.queue.dispatch(
                NodeInfoFetchJob.self,
                NodeInfoFetchPayload(domain: subscriber.domain),
                maxRetryCount: 0
            )
        }
    }
}

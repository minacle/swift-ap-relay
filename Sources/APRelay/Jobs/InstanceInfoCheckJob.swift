import Queues
import Vapor

/// Periodically dispatches ``InstanceInfoFetchJob`` for each accepted subscriber.
///
/// The actual HTTP fetching happens in individual queue jobs, so worker count
/// naturally limits concurrent outbound requests.
struct InstanceInfoCheckJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let app = context.application
        let subscribers = try await app.repository.getAllSubscribers(state: .accepted)
        guard !subscribers.isEmpty else { return }

        for subscriber in subscribers {
            try await app.queues.queue.dispatch(
                InstanceInfoFetchJob.self,
                InstanceInfoFetchPayload(domain: subscriber.domain),
                maxRetryCount: 0
            )
        }
    }
}

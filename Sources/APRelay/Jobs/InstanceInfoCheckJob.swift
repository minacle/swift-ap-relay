import Foundation
import Queues
import Vapor

/// Periodically dispatches ``InstanceInfoFetchJob`` for each accepted subscriber.
///
/// Doubles as a reachability heartbeat — every check updates `isReachable` /
/// `lastCheckedAt`. Subscribers currently in a backoff window (set by a prior
/// failure) are skipped until their `nextAttemptAt` elapses.
struct InstanceInfoCheckJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let app = context.application
        let subscribers = try await app.repository.getAllSubscribers(state: .accepted)
        guard !subscribers.isEmpty else { return }

        let domains = subscribers.map(\.domain)
        let cached: [String: InstanceInfo]
        do {
            cached = try await app.instanceInfoCache.getAllInstanceInfo(domains: domains)
        } catch {
            // On cache failure, skip this tick rather than bypassing backoff and
            // flooding every subscriber. The next tick will retry.
            context.logger.warning("Failed to load cached instance info; skipping this check tick: \(error)")
            return
        }
        let now = Date()

        for subscriber in subscribers {
            if let entry = cached[subscriber.domain],
               let next = entry.nextAttemptAt,
               next > now
            {
                context.logger.trace("Skip instance info check for \(subscriber.domain): next attempt at \(next)")
                continue
            }

            try await app.queues.queue(.instanceInfo).dispatch(
                InstanceInfoFetchJob.self,
                InstanceInfoFetchPayload(domain: subscriber.domain),
                maxRetryCount: 0
            )
        }
    }
}

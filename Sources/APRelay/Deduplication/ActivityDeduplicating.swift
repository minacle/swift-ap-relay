/// Protocol abstracting activity deduplication.
///
/// Implementations include ``RedisActivityDeduplicator`` for production
/// and a mock actor for tests.
protocol ActivityDeduplicating: Sendable {
    /// Returns `true` if this activity ID was already seen recently.
    /// If not seen, records it atomically so subsequent calls return `true`.
    func isDuplicate(_ activityID: String) async throws -> Bool
}

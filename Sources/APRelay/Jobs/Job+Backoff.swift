import Queues

extension Job {
    /// Computes an exponentially increasing backoff delay with equal jitter.
    ///
    /// - Parameters:
    ///   - attempt: 1-based attempt number.
    ///   - base: Delay in seconds for `attempt == 1` (before jitter).
    ///   - maxInterval: Upper bound on the delay in seconds.
    ///   - jitter: Fraction of the delay to randomize, in `0...1`.
    ///     `0` disables jitter. `0.5` yields classic equal jitter
    ///     (delay ∈ `[raw/2, raw]`). `1.0` yields full jitter (`[0, raw]`).
    /// - Returns: Delay in seconds.
    @inlinable
    static func exponentialBackoffSeconds(
        attempt: Int,
        base: Int,
        maxInterval: Int,
        jitter: Double = 0.5,
    ) -> Int {
        guard attempt > 0 else { return 0 }
        let shift = min(attempt - 1, 30)
        let raw = min(base << shift, maxInterval)
        let clampedJitter = min(max(jitter, 0), 1)
        let fixed = Double(raw) * (1 - clampedJitter)
        let randomRange = Double(raw) * clampedJitter
        return min(Int(fixed + Double.random(in: 0...randomRange)), maxInterval)
    }
}

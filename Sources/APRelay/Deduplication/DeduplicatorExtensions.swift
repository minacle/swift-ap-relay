import Vapor

// MARK: - App Storage for ActivityDeduplicating

private struct DeduplicatorOverrideKey: StorageKey {
    typealias Value = any ActivityDeduplicating
}

extension Application {
    /// The activity deduplicator.
    ///
    /// In production this returns a ``RedisActivityDeduplicator`` backed by `app.redis`.
    /// In tests, set `deduplicatorOverride` to inject a mock.
    var activityDeduplicator: any ActivityDeduplicating {
        if let override = storage[DeduplicatorOverrideKey.self] {
            return override
        }
        return RedisActivityDeduplicator(redis: self.redis)
    }

    /// Override the deduplicator (used by tests to inject a mock).
    var deduplicatorOverride: (any ActivityDeduplicating)? {
        get { storage[DeduplicatorOverrideKey.self] }
        set { storage[DeduplicatorOverrideKey.self] = newValue }
    }
}

extension Request {
    /// The activity deduplicator for this request.
    var activityDeduplicator: any ActivityDeduplicating {
        if let override = application.storage[DeduplicatorOverrideKey.self] {
            return override
        }
        return RedisActivityDeduplicator(redis: self.redis)
    }
}

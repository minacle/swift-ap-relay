import Vapor

// MARK: - App Storage for InstanceInfoCaching

private struct InstanceInfoCacheOverrideKey: StorageKey {
    typealias Value = any InstanceInfoCaching
}

extension Application {
    /// The instance info cache.
    ///
    /// In production this returns a ``RedisInstanceInfoCache`` backed by `app.redis`.
    /// In tests, set `instanceInfoCacheOverride` to inject a mock.
    var instanceInfoCache: any InstanceInfoCaching {
        if let override = storage[InstanceInfoCacheOverrideKey.self] {
            return override
        }
        return RedisInstanceInfoCache(redis: self.redis, ttlSeconds: self.relayConfig.instanceInfoCheckInterval * 3)
    }

    /// Override the instance info cache (used by tests to inject a mock).
    var instanceInfoCacheOverride: (any InstanceInfoCaching)? {
        get { storage[InstanceInfoCacheOverrideKey.self] }
        set { storage[InstanceInfoCacheOverrideKey.self] = newValue }
    }
}

extension Request {
    /// The instance info cache for this request.
    var instanceInfoCache: any InstanceInfoCaching {
        application.instanceInfoCache
    }
}

import Vapor

// MARK: - App Storage for NodeInfoCaching

private struct NodeInfoCacheOverrideKey: StorageKey {
    typealias Value = any NodeInfoCaching
}

extension Application {
    /// The NodeInfo cache.
    ///
    /// In production this returns a ``RedisNodeInfoCache`` backed by `app.redis`.
    /// In tests, set `nodeInfoCacheOverride` to inject a mock.
    var nodeInfoCache: any NodeInfoCaching {
        if let override = storage[NodeInfoCacheOverrideKey.self] {
            return override
        }
        return RedisNodeInfoCache(redis: self.redis, ttlSeconds: self.relayConfig.nodeInfoCheckInterval * 3)
    }

    /// Override the NodeInfo cache (used by tests to inject a mock).
    var nodeInfoCacheOverride: (any NodeInfoCaching)? {
        get { storage[NodeInfoCacheOverrideKey.self] }
        set { storage[NodeInfoCacheOverrideKey.self] = newValue }
    }
}

extension Request {
    /// The NodeInfo cache for this request.
    var nodeInfoCache: any NodeInfoCaching {
        application.nodeInfoCache
    }
}

import Vapor

// MARK: - App Storage for RelayRepository

private struct RepositoryOverrideKey: StorageKey {
    typealias Value = any RelayRepository
}

extension Application {
    /// The relay data repository.
    ///
    /// In production this returns a ``RedisRelayRepository`` backed by `app.redis`.
    /// In tests, set `repositoryOverride` to inject a mock.
    var repository: any RelayRepository {
        if let override = storage[RepositoryOverrideKey.self] {
            return override
        }
        return RedisRelayRepository(redis: self.redis)
    }

    /// Override the repository (used by tests to inject a mock).
    var repositoryOverride: (any RelayRepository)? {
        get { storage[RepositoryOverrideKey.self] }
        set { storage[RepositoryOverrideKey.self] = newValue }
    }
}

extension Request {
    /// The relay data repository for this request.
    var repository: any RelayRepository {
        if let override = application.storage[RepositoryOverrideKey.self] {
            return override
        }
        return RedisRelayRepository(redis: self.redis)
    }
}

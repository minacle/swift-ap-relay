import APRelayCore
import Leaf
import Metrics
import Prometheus
import Queues
import QueuesRedisDriver
import Redis
import Vapor

func configure(_ app: Application) async throws {
    // Bootstrap Prometheus metrics (once per process).
    if app.environment != .testing {
        let registry = PrometheusCollectorRegistry()
        MetricsSystem.bootstrap(PrometheusMetricsFactory(registry: registry))
        app.prometheusRegistry = registry
    }

    let config = try makeRelayConfiguration()

    // Store config in app storage.
    app.relayConfig = config

    // Configure Redis and Queues.
    if app.environment != .testing {
        let redisConfig = try RedisConfiguration(url: config.redisURL)
        app.redis.configuration = redisConfig
        app.queues.use(.redis(redisConfig))

        // Register queue jobs.
        app.queues.add(DeliveryJob())
        app.queues.add(AcceptJob())
        app.queues.add(RejectJob())
    }

    // Initialize signing key after Redis pools are ready.
    // Must be registered after `app.redis.configuration` so that
    // Redis's lifecycle handler (which creates connection pools) runs first.
    app.lifecycle.use(SigningKeyBootstrap())

    // Start queue workers in non-testing environments.
    if app.environment != .testing {
        try app.queues.startInProcessJobs()
    }

    // Register admin commands.
    app.asyncCommands.use(ListSubscribersCommand(), as: "list-subscribers")
    app.asyncCommands.use(AcceptCommand(), as: "accept")
    app.asyncCommands.use(RejectCommand(), as: "reject")
    app.asyncCommands.use(BlockCommand(), as: "block")
    app.asyncCommands.use(UnblockCommand(), as: "unblock")
    app.asyncCommands.use(ListBlockedDomainsCommand(), as: "list-blocked-domains")

    // Configure Leaf view renderer.
    app.views.use(.leaf)

    // Register routes.
    try routes(app)
}

// MARK: - Signing Key Lifecycle Bootstrap

private struct SigningKeyBootstrap: LifecycleHandler {
    func didBootAsync(_ application: Application) async throws {
        let keyManager = KeyManager(repository: application.repository)
        let privateKey = try await keyManager.getOrCreatePrivateKey()
        application.signingKey = privateKey

        let keyID = "\(application.relayConfig.actorURL)#main-key"
        application.actorFetcher = HTTPActorFetcher(
            privateKey: privateKey,
            keyID: keyID
        )
    }
}

// MARK: - App Storage for RelayConfiguration

private struct RelayConfigKey: StorageKey {
    typealias Value = RelayConfiguration
}

extension Application {
    var relayConfig: RelayConfiguration {
        get {
            guard let config = storage[RelayConfigKey.self] else {
                fatalError("RelayConfiguration not configured. Call configure() first.")
            }
            return config
        }
        set {
            storage[RelayConfigKey.self] = newValue
        }
    }
}

extension Request {
    var relayConfig: RelayConfiguration {
        application.relayConfig
    }
}

// MARK: - App Storage for PrometheusCollectorRegistry

private struct PrometheusRegistryKey: StorageKey {
    typealias Value = PrometheusCollectorRegistry
}

extension Application {
    var prometheusRegistry: PrometheusCollectorRegistry? {
        get { storage[PrometheusRegistryKey.self] }
        set { storage[PrometheusRegistryKey.self] = newValue }
    }
}

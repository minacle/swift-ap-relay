import APRelayCore
import Leaf
import Metrics
import Prometheus
import Queues
import QueuesRedisDriver
import Redis
import Vapor

func configure(_ app: Application) async throws {
    // Register shared JSON encoder for deterministic key ordering (cache-friendly).
    ContentConfiguration.global.use(encoder: JSONEncoder.apRelay, for: .json)
    ContentConfiguration.global.use(encoder: JSONEncoder.apRelay, for: .init(type: "application", subType: "activity+json"))
    ContentConfiguration.global.use(encoder: JSONEncoder.apRelay, for: .init(type: "application", subType: "jrd+json"))

    // Bootstrap Prometheus metrics (once per process).
    if app.environment != .testing {
        let registry = PrometheusCollectorRegistry()
        MetricsSystem.bootstrap(PrometheusMetricsFactory(registry: registry))
        app.prometheusRegistry = registry
    }

    let config = try makeRelayConfiguration()

    // Store config in app storage.
    app.relayConfig = config

    // Set Server response header and User-Agent identity.
    app.http.server.configuration.serverName = AppInfo.userAgent(config: config)

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

    // Server-only setup: signing key and in-process queue workers require
    // a live Redis connection at boot, so only register them for `serve`.
    let args = app.environment.commandInput.arguments
    let isHelp = args.contains("--help") || args.contains("-h")
    let commandName = args.first ?? "serve"
    if commandName == "serve" && !isHelp {
        // Initialize signing key after Redis pools are ready.
        // Must be registered after `app.redis.configuration` so that
        // Redis's lifecycle handler (which creates connection pools) runs first.
        app.lifecycle.use(SigningKeyBootstrap())

        // Start queue workers in non-testing environments.
        if app.environment != .testing {
            try app.queues.startInProcessJobs()
        }
    }

    // Register admin commands.
    app.asyncCommands.use(AdminCommandGroup(), as: "admin")

    // Configure Leaf view renderer.
    app.views.use(.leaf)

    // Configure localizer with translation files.
    let localesDir = app.directory.resourcesDirectory + "Locales"
    app.localizer = try Localizer(directory: localesDir)

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
            keyID: keyID,
            userAgent: AppInfo.userAgent(config: application.relayConfig)
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

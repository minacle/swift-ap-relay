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
        app.queues.add(InstanceInfoFetchJob())

        // Schedule periodic instance info check.
        app.queues.schedule(InstanceInfoCheckJob())
            .every(seconds: config.instanceInfoCheckInterval)
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

        // Start a dedicated metrics server when METRICS_BIND is set.
        if let metricsBind = Environment.get("METRICS_BIND"),
           let registry = app.prometheusRegistry {
            let (hostname, port) = parseBindAddress(metricsBind)
            app.lifecycle.use(MetricsServerLifecycle(registry: registry, hostname: hostname, port: port))
        }

        // Start queue workers and scheduled jobs in non-testing environments.
        if app.environment != .testing {
            try app.queues.startInProcessJobs()
            try app.queues.startScheduledJobs()

            // Immediately fetch instance info for existing subscribers at boot.
            let subscribers = try await app.repository.getAllSubscribers(state: .accepted)
            for subscriber in subscribers {
                try await app.queues.queue.dispatch(
                    InstanceInfoFetchJob.self,
                    InstanceInfoFetchPayload(domain: subscriber.domain),
                    maxRetryCount: 0
                )
            }
        }
    }

    // Register admin commands.
    app.asyncCommands.use(AdminCommandGroup(), as: "admin")

    // Configure Leaf view renderer.
    app.views.use(.leaf)

    // Serve static files from the Public directory.
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

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

// MARK: - Metrics Server on Separate Port

/// Parses a bind address string into hostname and port.
///
/// - `"0.0.0.0:9090"` → `("0.0.0.0", 9090)`
/// - `":9090"` → `("0.0.0.0", 9090)`
/// - `"9090"` → `("0.0.0.0", 9090)`
///
/// Throws a fatal error if the value cannot be parsed.
private func parseBindAddress(_ value: String) -> (hostname: String, port: Int) {
    let parts = value.split(separator: ":", maxSplits: 1)
    if parts.count == 2 {
        let host = parts[0].isEmpty ? "0.0.0.0" : String(parts[0])
        guard let port = Int(parts[1]) else {
            fatalError("Invalid METRICS_BIND port: \(parts[1]) (expected integer)")
        }
        return (host, port)
    }
    if let port = Int(value) {
        return ("0.0.0.0", port)
    }
    fatalError("Invalid METRICS_BIND value: \(value) (expected [host]:port)")
}

private struct MetricsAppKey: StorageKey {
    typealias Value = Application
}

private struct MetricsServerLifecycle: LifecycleHandler {
    let registry: PrometheusCollectorRegistry
    let hostname: String
    let port: Int

    func didBootAsync(_ application: Application) async throws {
        let metricsApp = try await Application.make(application.environment)
        metricsApp.http.server.configuration.hostname = hostname
        metricsApp.http.server.configuration.port = port

        let registry = self.registry
        metricsApp.get("metrics") { _ in
            registry.emitToString()
        }

        try await metricsApp.server.start(address: nil)
        application.storage[MetricsAppKey.self] = metricsApp

        application.logger.info("Metrics server started on \(hostname):\(port)")
    }

    func shutdownAsync(_ application: Application) async throws {
        guard let metricsApp = application.storage[MetricsAppKey.self] else { return }
        await metricsApp.server.shutdown()
        try await metricsApp.asyncShutdown()
        application.storage[MetricsAppKey.self] = nil
    }
}

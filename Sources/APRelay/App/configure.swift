import APRelayCore
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Metrics
import Prometheus
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

    // Configure HTTP server.
    app.http.server.configuration.hostname = config.host
    app.http.server.configuration.port = config.port

    // Configure database (use in-memory SQLite for testing).
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        try configureDatabase(app, url: config.databaseURL)
    }

    // Register migrations.
    app.migrations.add(CreateSubscribers())
    app.migrations.add(CreateBlockedDomains())
    app.migrations.add(CreateAllowedDomains())
    app.migrations.add(CreateRelaySettings())
    app.migrations.add(AddFollowObjectURIToSubscribers())

    try await app.autoMigrate()

    // Initialize delivery service.
    let keyManager = KeyManager(db: app.db)
    let privateKey = try await keyManager.getOrCreatePrivateKey()
    app.deliveryService = DeliveryService(
        client: app.client,
        config: config,
        privateKey: privateKey,
        logger: app.logger
    )

    // Register admin commands.
    app.asyncCommands.use(ListSubscribersCommand(), as: "list-subscribers")
    app.asyncCommands.use(AcceptCommand(), as: "accept")
    app.asyncCommands.use(RejectCommand(), as: "reject")
    app.asyncCommands.use(BlockCommand(), as: "block")
    app.asyncCommands.use(UnblockCommand(), as: "unblock")

    // Register routes.
    try routes(app)
}

private func configureDatabase(_ app: Application, url: String) throws {
    if url.hasPrefix("postgres://") || url.hasPrefix("postgresql://") {
        guard let postgresURL = URLComponents(string: url) else {
            throw Abort(.internalServerError, reason: "Invalid DATABASE_URL: \(url)")
        }
        let tlsConfig: DatabaseConfigurationFactory = .postgres(
            configuration: .init(
                hostname: postgresURL.host ?? "localhost",
                port: postgresURL.port ?? 5432,
                username: postgresURL.user ?? "postgres",
                password: postgresURL.password,
                database: String(postgresURL.path.dropFirst()),
                tls: .disable
            )
        )
        app.databases.use(tlsConfig, as: .psql)
    } else if url.hasPrefix("sqlite:") {
        let path = String(url.dropFirst("sqlite:".count))
        if path == ":memory:" {
            app.databases.use(.sqlite(.memory), as: .sqlite)
        } else {
            app.databases.use(.sqlite(.file(path)), as: .sqlite)
        }
    } else {
        throw Abort(.internalServerError, reason: "Invalid DATABASE_URL: \(url)")
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

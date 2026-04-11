import Vapor
import XCTQueues
@testable import APRelay

/// Configures the app for testing with mock repository and actor fetcher.
func testConfigure(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "false", 1)
    setenv("RESTRICTED_MODE", "false", 1)
    app.repositoryOverride = MockRelayRepository()
    app.queues.use(.asyncTest)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

/// Configures the app with manual accept mode enabled.
func testConfigureManualAccept(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "true", 1)
    setenv("RESTRICTED_MODE", "false", 1)
    app.repositoryOverride = MockRelayRepository()
    app.queues.use(.asyncTest)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

/// Configures the app with restricted mode enabled.
func testConfigureRestricted(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "false", 1)
    setenv("RESTRICTED_MODE", "true", 1)
    app.repositoryOverride = MockRelayRepository()
    app.queues.use(.asyncTest)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

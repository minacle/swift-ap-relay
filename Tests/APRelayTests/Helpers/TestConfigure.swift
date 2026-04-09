import Vapor
@testable import APRelay

/// Configures the app for testing with in-memory database and mock actor fetcher.
func testConfigure(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "false", 1)
    setenv("RESTRICTED_MODE", "false", 1)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

/// Configures the app with manual accept mode enabled.
func testConfigureManualAccept(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "true", 1)
    setenv("RESTRICTED_MODE", "false", 1)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

/// Configures the app with restricted mode enabled.
func testConfigureRestricted(_ app: Application) async throws {
    setenv("RELAY_DOMAIN", "localhost", 1)
    setenv("ADMIN_TOKEN", "test-token", 1)
    setenv("MANUAL_ACCEPT", "false", 1)
    setenv("RESTRICTED_MODE", "true", 1)
    try await APRelay.configure(app)
    app.actorFetcher = MockActorFetcher()
}

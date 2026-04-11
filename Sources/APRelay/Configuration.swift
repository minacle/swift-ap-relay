import APRelayCore
import Vapor

/// Creates a `RelayConfiguration` from Vapor environment variables.
func makeRelayConfiguration() throws -> RelayConfiguration {
    guard let domain = Environment.get("RELAY_DOMAIN") else {
        throw Abort(.internalServerError, reason: "Missing required environment variable: RELAY_DOMAIN")
    }
    return RelayConfiguration(
        domain: domain,
        scheme: Environment.get("RELAY_SCHEME") ?? "https",
        host: Environment.get("RELAY_HOST") ?? "0.0.0.0",
        port: Environment.get("RELAY_PORT").flatMap(Int.init) ?? 8080,
        redisURL: Environment.get("REDIS_URL") ?? "redis://localhost:6379",
        adminToken: Environment.get("ADMIN_TOKEN") ?? "",
        manualAccept: Environment.get("MANUAL_ACCEPT") == "true",
        restrictedMode: Environment.get("RESTRICTED_MODE") == "true",
        relayDescription: Environment.get("RELAY_DESCRIPTION") ?? "",
        relayFooter: Environment.get("RELAY_FOOTER") ?? ""
    )
}

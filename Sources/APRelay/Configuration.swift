import APRelayCore
import Vapor

/// Creates a `RelayConfiguration` from Vapor environment variables.
func makeRelayConfiguration() throws -> RelayConfiguration {
    let baseURL = Environment.get("RELAY_URL") ?? "http://127.0.0.1:8080"
    return RelayConfiguration(
        baseURL: baseURL,
        redisURL: Environment.get("REDIS_URL") ?? "redis://localhost:6379",
        adminToken: Environment.get("ADMIN_TOKEN") ?? "",
        manualAccept: Environment.get("MANUAL_ACCEPT") == "true",
        restrictedMode: Environment.get("RESTRICTED_MODE") == "true",
        relayDescription: Environment.get("RELAY_DESCRIPTION") ?? "",
        relayFooter: Environment.get("RELAY_FOOTER") ?? ""
    )
}

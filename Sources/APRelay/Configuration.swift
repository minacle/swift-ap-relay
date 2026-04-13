import APRelayCore
import Foundation
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
        instanceInfoCheckInterval: max(Environment.get("INSTANCE_INFO_CHECK_INTERVAL").flatMap(Int.init) ?? 300, 60),
        relayName: buildLocalizedString(envPrefix: "RELAY_NAME"),
        relayDescription: buildLocalizedString(envPrefix: "RELAY_DESCRIPTION"),
        relayFooter: buildLocalizedString(envPrefix: "RELAY_FOOTER"),
        allowedPrivateAddresses: parseCommaSeparatedEnv("ALLOWED_PRIVATE_ADDRESSES"),
        defaultQueueWorkerCount: Environment.get("DEFAULT_QUEUE_WORKER_COUNT").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil },
        deliveryQueueWorkerCount: Environment.get("DELIVERY_QUEUE_WORKER_COUNT").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
    )
}

// MARK: - Comma-Separated Env Var Helper

/// Parses a comma-separated environment variable into a trimmed array of strings.
///
/// - `"192.168.1.0/24, 10.0.0.0/8"` → `["192.168.1.0/24", "10.0.0.0/8"]`
/// - `nil` or `""` → `[]`
private func parseCommaSeparatedEnv(_ key: String) -> [String] {
    guard let value = Environment.get(key), !value.isEmpty else { return [] }
    return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Localized Env Var Helpers

/// Scans `ProcessInfo.processInfo.environment` for keys matching
/// `{envPrefix}` and `{envPrefix}__{LOCALE}`, building a `LocalizedString`.
///
/// - `RELAY_NAME` → `"und"` key
/// - `RELAY_NAME__KO` → `"ko"` key
/// - `RELAY_NAME__ZH_TW` → `"zh-TW"` key
private func buildLocalizedString(envPrefix: String) -> LocalizedString {
    let env = ProcessInfo.processInfo.environment
    var values: [String: String] = [:]

    // Base value (no suffix) → "und"
    if let base = env[envPrefix], !base.isEmpty {
        values["und"] = base
    }

    // Scan for locale-suffixed variants (double underscore separator)
    let prefix = envPrefix + "__"
    for (key, value) in env where key.hasPrefix(prefix) && !value.isEmpty {
        let suffix = String(key.dropFirst(prefix.count))
        let locale = parseEnvLocaleSuffix(suffix)
        values[locale] = value
    }

    return LocalizedString(values)
}

/// Converts an env var locale suffix to a BCP 47 locale identifier.
///
/// - `KO` → `"ko"`
/// - `ZH_TW` → `"zh-TW"`
/// - `ZH_HANT_TW` → `"zh-Hant-TW"`
/// - `SR_LATN` → `"sr-Latn"`
private func parseEnvLocaleSuffix(_ suffix: String) -> String {
    let parts = suffix.split(separator: "_")
    guard let first = parts.first else { return suffix.lowercased() }
    let language = first.lowercased()
    if parts.count > 1 {
        let subtags = parts.dropFirst().map { subtag -> String in
            if subtag.count == 4 && subtag.allSatisfy(\.isLetter) {
                // Script subtag: Title Case (e.g., Hant, Latn)
                return subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
            } else {
                // Region subtag (2 letters / 3 digits) or variant
                return subtag.uppercased()
            }
        }.joined(separator: "-")
        return "\(language)-\(subtags)"
    }
    return language
}

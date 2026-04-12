import APRelayCore
import Vapor

enum AppInfo {
    /// Version string. Checks `AP_RELAY_VERSION` env var first,
    /// then falls back to the build-time `git describe` value.
    static var version: String {
        if let envVersion = Environment.get("AP_RELAY_VERSION"),
           !envVersion.isEmpty
        {
            return envVersion
        }
        let generated = GeneratedBuildInfo.version
        return generated.isEmpty ? "dev" : generated
    }

    /// Source commit hash. Checks `SOURCE_COMMIT` env var first,
    /// then falls back to the build-time `git rev-parse HEAD` value.
    static var sourceCommit: String? {
        if let envCommit = Environment.get("SOURCE_COMMIT"),
           !envCommit.isEmpty
        {
            return envCommit
        }
        let generated = GeneratedBuildInfo.commit
        return generated.isEmpty ? nil : generated
    }

    /// Short commit hash (first 7 characters) for display.
    static var shortCommit: String? {
        sourceCommit.map { String($0.prefix(7)) }
    }

    /// GitHub source URL for the current commit.
    static var sourceURL: String? {
        sourceCommit.map {
            "https://github.com/sinoru/swift-ap-relay/tree/\($0)"
        }
    }

    /// User-Agent string for outgoing HTTP requests and Server response header.
    ///
    /// Format: `APRelay/{version} ({name}; +{baseURL})`
    static func userAgent(config: RelayConfiguration) -> String {
        let name = config.relayName.unlocalizedValue() ?? config.domain
        return "APRelay/\(version) (\(name); +\(config.baseURL))"
    }
}

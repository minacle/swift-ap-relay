import Foundation

/// Relay server configuration.
///
/// A pure value type with no framework dependencies. The caller is responsible
/// for populating values from environment variables, .env files, etc.
public struct RelayConfiguration: Sendable {
    public let domain: String
    public let scheme: String
    public let host: String
    public let port: Int
    public let redisURL: String
    public let adminToken: String
    public let manualAccept: Bool
    public let restrictedMode: Bool
    public let relayDescription: String
    public let relayFooter: String

    public var baseURL: String {
        "\(scheme)://\(domain)"
    }

    public var actorURL: String {
        "\(baseURL)/actor"
    }

    public var inboxURL: String {
        "\(baseURL)/inbox"
    }

    public init(
        domain: String,
        scheme: String = "https",
        host: String = "0.0.0.0",
        port: Int = 8080,
        redisURL: String = "redis://localhost:6379",
        adminToken: String = "",
        manualAccept: Bool = false,
        restrictedMode: Bool = false,
        relayDescription: String = "",
        relayFooter: String = ""
    ) {
        self.domain = domain
        self.scheme = scheme
        self.host = host
        self.port = port
        self.redisURL = redisURL
        self.adminToken = adminToken
        self.manualAccept = manualAccept
        self.restrictedMode = restrictedMode
        self.relayDescription = relayDescription
        self.relayFooter = relayFooter
    }
}

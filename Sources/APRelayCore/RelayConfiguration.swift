import Foundation

/// Relay server configuration.
///
/// A pure value type with no framework dependencies. The caller is responsible
/// for populating values from environment variables, .env files, etc.
public struct RelayConfiguration: Sendable {
    public let baseURL: String
    public let domain: String
    public let redisURL: String
    public let adminToken: String
    public let manualAccept: Bool
    public let restrictedMode: Bool
    public let relayDescription: String
    public let relayFooter: String

    public var actorURL: String {
        "\(baseURL)/actor"
    }

    public var inboxURL: String {
        "\(baseURL)/inbox"
    }

    public init(
        baseURL: String,
        redisURL: String = "redis://localhost:6379",
        adminToken: String = "",
        manualAccept: Bool = false,
        restrictedMode: Bool = false,
        relayDescription: String = "",
        relayFooter: String = ""
    ) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if let url = URL(string: self.baseURL) {
            self.domain = url.host() ?? self.baseURL
        } else {
            self.domain = self.baseURL
        }
        self.redisURL = redisURL
        self.adminToken = adminToken
        self.manualAccept = manualAccept
        self.restrictedMode = restrictedMode
        self.relayDescription = relayDescription
        self.relayFooter = relayFooter
    }
}

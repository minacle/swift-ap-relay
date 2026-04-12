import Foundation

/// Relay server configuration.
///
/// A pure value type with no framework dependencies. The caller is responsible
/// for populating values from environment variables, .env files, etc.
package struct RelayConfiguration: Sendable {
    package let baseURL: String
    package let domain: String
    package let redisURL: String
    package let adminToken: String
    package let manualAccept: Bool
    package let restrictedMode: Bool
    package let instanceInfoCheckInterval: Int
    package let relayName: LocalizedString
    package let relayDescription: LocalizedString
    package let relayFooter: LocalizedString
    package let allowedPrivateAddresses: [String]

    package var actorURL: String {
        "\(baseURL)/actor"
    }

    package var inboxURL: String {
        "\(baseURL)/inbox"
    }

    package init(
        baseURL: String,
        redisURL: String = "redis://localhost:6379",
        adminToken: String = "",
        manualAccept: Bool = false,
        restrictedMode: Bool = false,
        instanceInfoCheckInterval: Int = 300,
        relayName: LocalizedString = LocalizedString([:]),
        relayDescription: LocalizedString = LocalizedString([:]),
        relayFooter: LocalizedString = LocalizedString([:]),
        allowedPrivateAddresses: [String] = []
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
        self.instanceInfoCheckInterval = instanceInfoCheckInterval
        self.relayName = relayName
        self.relayDescription = relayDescription
        self.relayFooter = relayFooter
        self.allowedPrivateAddresses = allowedPrivateAddresses
    }
}

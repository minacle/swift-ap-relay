import Foundation

/// Cached NodeInfo data fetched from a remote server.
package struct RemoteNodeInfo: Codable, Sendable {
    package let softwareName: String?
    package let softwareVersion: String?
    package let openRegistrations: Bool?
    package let staffAccounts: [String]?
    package let isReachable: Bool
    package let lastCheckedAt: Date

    package init(
        softwareName: String? = nil,
        softwareVersion: String? = nil,
        openRegistrations: Bool? = nil,
        staffAccounts: [String]? = nil,
        isReachable: Bool,
        lastCheckedAt: Date
    ) {
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.openRegistrations = openRegistrations
        self.staffAccounts = staffAccounts
        self.isReachable = isReachable
        self.lastCheckedAt = lastCheckedAt
    }
}

import Foundation

/// Cached instance metadata fetched from a remote server.
struct InstanceInfo: Codable, Sendable {
    let softwareName: String?
    let softwareVersion: String?
    let openRegistrations: Bool?
    let staffAccounts: [String]?
    let faviconURL: String?
    let isReachable: Bool
    let lastCheckedAt: Date

    init(
        softwareName: String? = nil,
        softwareVersion: String? = nil,
        openRegistrations: Bool? = nil,
        staffAccounts: [String]? = nil,
        faviconURL: String? = nil,
        isReachable: Bool,
        lastCheckedAt: Date
    ) {
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.openRegistrations = openRegistrations
        self.staffAccounts = staffAccounts
        self.faviconURL = faviconURL
        self.isReachable = isReachable
        self.lastCheckedAt = lastCheckedAt
    }
}

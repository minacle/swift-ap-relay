import Foundation

/// Cached instance metadata fetched from a remote server.
struct InstanceInfo: Sendable {
    let softwareName: String?
    let softwareVersion: String?
    let openRegistrations: Bool?
    let staffAccounts: [String]?
    let faviconURL: String?
    let isReachable: Bool
    let lastCheckedAt: Date
    let consecutiveFailures: Int
    let nextAttemptAt: Date?

    init(
        softwareName: String? = nil,
        softwareVersion: String? = nil,
        openRegistrations: Bool? = nil,
        staffAccounts: [String]? = nil,
        faviconURL: String? = nil,
        isReachable: Bool,
        lastCheckedAt: Date,
        consecutiveFailures: Int = 0,
        nextAttemptAt: Date? = nil
    ) {
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.openRegistrations = openRegistrations
        self.staffAccounts = staffAccounts
        self.faviconURL = faviconURL
        self.isReachable = isReachable
        self.lastCheckedAt = lastCheckedAt
        self.consecutiveFailures = consecutiveFailures
        self.nextAttemptAt = nextAttemptAt
    }
}

extension InstanceInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case softwareName
        case softwareVersion
        case openRegistrations
        case staffAccounts
        case faviconURL
        case isReachable
        case lastCheckedAt
        case consecutiveFailures
        case nextAttemptAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.softwareName = try container.decodeIfPresent(String.self, forKey: .softwareName)
        self.softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
        self.openRegistrations = try container.decodeIfPresent(Bool.self, forKey: .openRegistrations)
        self.staffAccounts = try container.decodeIfPresent([String].self, forKey: .staffAccounts)
        self.faviconURL = try container.decodeIfPresent(String.self, forKey: .faviconURL)
        self.isReachable = try container.decode(Bool.self, forKey: .isReachable)
        self.lastCheckedAt = try container.decode(Date.self, forKey: .lastCheckedAt)
        self.consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        self.nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
    }
}

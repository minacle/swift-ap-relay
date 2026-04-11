/// Protocol abstracting all data access operations for the relay.
///
/// Implementations include ``RedisRelayRepository`` for production
/// and a mock actor for tests.
protocol RelayRepository: Sendable {
    // MARK: - Subscribers

    func getSubscriber(domain: String) async throws -> Subscriber?
    func getAllSubscribers(state: SubscriberState?) async throws -> [Subscriber]
    func getAcceptedInboxURLs() async throws -> [String]
    func saveSubscriber(_ subscriber: Subscriber) async throws
    func deleteSubscriber(domain: String) async throws

    // MARK: - Blocked Domains

    func isBlocked(domain: String) async throws -> Bool
    func getAllBlockedDomains() async throws -> [BlockedDomain]
    func blockDomain(_ domain: String, reason: String?) async throws -> Bool
    func unblockDomain(_ domain: String) async throws -> Bool

    // MARK: - Allowed Domains

    func isAllowed(domain: String) async throws -> Bool

    // MARK: - Settings

    func getSetting(key: String) async throws -> String?
    func setSetting(key: String, value: String) async throws
}

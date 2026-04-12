/// Protocol abstracting instance info cache operations.
///
/// Implementations include ``RedisInstanceInfoCache`` for production
/// and a mock actor for tests.
protocol InstanceInfoCaching: Sendable {
    func getInstanceInfo(domain: String) async throws -> InstanceInfo?
    func setInstanceInfo(domain: String, info: InstanceInfo) async throws
    func getAllInstanceInfo(domains: [String]) async throws -> [String: InstanceInfo]
}

import APRelayCore

/// Protocol abstracting NodeInfo cache operations.
///
/// Implementations include ``RedisNodeInfoCache`` for production
/// and a mock actor for tests.
protocol NodeInfoCaching: Sendable {
    func getNodeInfo(domain: String) async throws -> RemoteNodeInfo?
    func setNodeInfo(domain: String, info: RemoteNodeInfo) async throws
    func getAllNodeInfo(domains: [String]) async throws -> [String: RemoteNodeInfo]
}

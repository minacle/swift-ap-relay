@testable import APRelay

/// In-memory implementation of ``InstanceInfoCaching`` for testing.
actor MockInstanceInfoCache: InstanceInfoCaching {
    private var store: [String: InstanceInfo] = .init()

    func getInstanceInfo(domain: String) async throws -> InstanceInfo? {
        store[domain]
    }

    func setInstanceInfo(domain: String, info: InstanceInfo) async throws {
        store[domain] = info
    }

    func getAllInstanceInfo(domains: [String]) async throws -> [String: InstanceInfo] {
        var result = [String: InstanceInfo]()
        for domain in domains {
            if let info = store[domain] {
                result[domain] = info
            }
        }
        return result
    }
}

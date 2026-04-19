import Foundation
@preconcurrency @unsafe import RediStack
import Vapor

/// Redis-backed implementation of ``InstanceInfoCaching``.
///
/// Stores each domain's instance info as a JSON string under `instanceinfo:{domain}`.
struct RedisInstanceInfoCache: InstanceInfoCaching, Sendable {
    /// Fixed TTL for cached entries. Decoupled from the check interval so that a
    /// tighter heartbeat cadence does not shrink the safety-net lifetime used to
    /// evict stale data for departed or long-offline instances.
    static let defaultTTLSeconds: Int = 3600

    let redis: any RedisClient & Sendable
    let ttlSeconds: Int

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func key(_ domain: String) -> RedisKey { "instanceinfo:\(domain)" }

    func getInstanceInfo(domain: String) async throws -> InstanceInfo? {
        let data = try await redis.get(key(domain), as: String.self).get()
        guard let json = data, let jsonData = json.data(using: .utf8) else { return nil }
        return try Self.decoder.decode(InstanceInfo.self, from: jsonData)
    }

    func setInstanceInfo(domain: String, info: InstanceInfo) async throws {
        let data = try Self.encoder.encode(info)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await redis.setex(key(domain), to: json, expirationInSeconds: ttlSeconds).get()
    }

    func getAllInstanceInfo(domains: [String]) async throws -> [String: InstanceInfo] {
        guard !domains.isEmpty else { return [:] }

        let keys = domains.map { key($0) }
        let values = try await redis.mget(keys, as: String.self).get()

        var result: [String: InstanceInfo] = [:]
        for (domain, value) in zip(domains, values) {
            guard let json = value, let jsonData = json.data(using: .utf8) else { continue }
            if let info = try? Self.decoder.decode(InstanceInfo.self, from: jsonData) {
                result[domain] = info
            }
        }
        return result
    }
}

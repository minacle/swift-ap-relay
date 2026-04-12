import APRelayCore
import Foundation
@preconcurrency @unsafe import RediStack
import Vapor

/// Redis-backed implementation of ``NodeInfoCaching``.
///
/// Stores each domain's NodeInfo as a JSON string under `nodeinfo:{domain}`.
struct RedisNodeInfoCache: NodeInfoCaching, Sendable {
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

    private func key(_ domain: String) -> RedisKey { "nodeinfo:\(domain)" }

    func getNodeInfo(domain: String) async throws -> RemoteNodeInfo? {
        let data = try await redis.get(key(domain), as: String.self).get()
        guard let json = data, let jsonData = json.data(using: .utf8) else { return nil }
        return try Self.decoder.decode(RemoteNodeInfo.self, from: jsonData)
    }

    func setNodeInfo(domain: String, info: RemoteNodeInfo) async throws {
        let data = try Self.encoder.encode(info)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await redis.setex(key(domain), to: json, expirationInSeconds: ttlSeconds).get()
    }

    func getAllNodeInfo(domains: [String]) async throws -> [String: RemoteNodeInfo] {
        guard !domains.isEmpty else { return [:] }

        let keys = domains.map { key($0) }
        let values = try await redis.mget(keys, as: String.self).get()

        var result: [String: RemoteNodeInfo] = [:]
        for (domain, value) in zip(domains, values) {
            guard let json = value, let jsonData = json.data(using: .utf8) else { continue }
            if let info = try? Self.decoder.decode(RemoteNodeInfo.self, from: jsonData) {
                result[domain] = info
            }
        }
        return result
    }
}

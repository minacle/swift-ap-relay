@preconcurrency @unsafe import RediStack
import Vapor

/// Redis-backed implementation of ``RelayRepository``.
///
/// Key schema:
/// - `subscriber:{domain}` — Hash with subscriber fields
/// - `subscribers:state:{state}` — Set of domains per state
/// - `subscribers:all` — Set of all subscriber domains
/// - `blocked_domains` — Set of blocked domain strings
/// - `blocked_domain:{domain}` — Hash with reason/createdAt
/// - `allowed_domains` — Set of allowed domain strings
/// - `relay_settings` — Hash of key-value settings
struct RedisRelayRepository: RelayRepository, Sendable {
    let redis: any RedisClient & Sendable

    private static let dateFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private func formatDate(_ date: Date) -> String {
        date.formatted(Self.dateFormatStyle)
    }

    private func parseDate(_ string: String) -> Date? {
        try? Self.dateFormatStyle.parse(string)
    }

    // MARK: - Key Helpers

    private func subscriberKey(_ domain: String) -> RedisKey { "subscriber:\(domain)" }
    private func stateSetKey(_ state: SubscriberState) -> RedisKey {
        "subscribers:state:\(state.rawValue)"
    }
    private var allSubscribersKey: RedisKey { "subscribers:all" }
    private var blockedDomainsSetKey: RedisKey { "blocked_domains" }
    private func blockedDomainKey(_ domain: String) -> RedisKey { "blocked_domain:\(domain)" }
    private var allowedDomainsSetKey: RedisKey { "allowed_domains" }
    private var settingsKey: RedisKey { "relay_settings" }

    // MARK: - Subscribers

    func getSubscriber(domain: String) async throws -> Subscriber? {
        let fields = try await redis.hgetall(from: subscriberKey(domain)).get()
        guard !fields.isEmpty else { return nil }
        return decodeSubscriber(domain: domain, fields: fields)
    }

    func getAllSubscribers(state: SubscriberState?) async throws -> [Subscriber] {
        let key = state.map { stateSetKey($0) } ?? allSubscribersKey
        let domainValues = try await redis.smembers(of: key).get()
        let domains = domainValues.compactMap(\.string)
        guard !domains.isEmpty else { return [] }

        let futures = domains.map { domain in
            redis.hgetall(from: subscriberKey(domain))
        }
        let results = try await EventLoopFuture.whenAllSucceed(futures, on: redis.eventLoop).get()

        return zip(domains, results).compactMap { (domain, fields) in
            guard !fields.isEmpty else { return nil }
            return decodeSubscriber(domain: domain, fields: fields)
        }
    }

    func getAcceptedInboxURLs() async throws -> [String] {
        let domainValues = try await redis.smembers(of: stateSetKey(.accepted)).get()
        let domains = domainValues.compactMap(\.string)
        guard !domains.isEmpty else { return [] }

        let futures = domains.map { domain in
            redis.hget("inboxURL", from: subscriberKey(domain))
        }
        let results = try await EventLoopFuture.whenAllSucceed(futures, on: redis.eventLoop).get()
        return results.compactMap(\.string)
    }

    func saveSubscriber(_ subscriber: Subscriber) async throws {
        let key = subscriberKey(subscriber.domain)
        let now = formatDate(Date())

        // Check existing state for set index management.
        let existingState = try await redis.hget("state", from: key).get().string

        let createdAt: String
        if let existing = try await redis.hget("createdAt", from: key).get().string {
            createdAt = existing
        } else {
            createdAt = subscriber.createdAt.map { formatDate($0) } ?? now
        }

        let fields: [String: RESPValue] = [
            "inboxURL": .init(from: subscriber.inboxURL),
            "actorID": .init(from: subscriber.actorID),
            "state": .init(from: subscriber.state.rawValue),
            "followActivityID": .init(from: subscriber.followActivityID),
            "followObjectURI": .init(from: subscriber.followObjectURI ?? ""),
            "createdAt": .init(from: createdAt),
            "updatedAt": .init(from: now),
        ]
        _ = try await redis.hmset(fields, in: key).get()
        _ = try await redis.sadd(subscriber.domain, to: allSubscribersKey).get()

        // Move between state sets if state changed.
        if let old = existingState, old != subscriber.state.rawValue,
            let oldState = SubscriberState(rawValue: old)
        {
            _ = try await redis.srem(subscriber.domain, from: stateSetKey(oldState)).get()
        }
        _ = try await redis.sadd(subscriber.domain, to: stateSetKey(subscriber.state)).get()
    }

    func deleteSubscriber(domain: String) async throws {
        let stateValue = try await redis.hget("state", from: subscriberKey(domain)).get().string

        _ = try await redis.send(
            command: "DEL",
            with: [.init(from: subscriberKey(domain).rawValue)]
        ).get()
        _ = try await redis.srem(domain, from: allSubscribersKey).get()

        if let stateRaw = stateValue, let state = SubscriberState(rawValue: stateRaw) {
            _ = try await redis.srem(domain, from: stateSetKey(state)).get()
        }
    }

    // MARK: - Blocked Domains

    func isBlocked(domain: String) async throws -> Bool {
        try await redis.sismember(domain, of: blockedDomainsSetKey).get()
    }

    func getAllBlockedDomains() async throws -> [BlockedDomain] {
        let domainValues = try await redis.smembers(of: blockedDomainsSetKey).get()
        let domains = domainValues.compactMap(\.string)
        guard !domains.isEmpty else { return [] }

        let futures = domains.map { domain in
            redis.hgetall(from: blockedDomainKey(domain))
        }
        let results = try await EventLoopFuture.whenAllSucceed(futures, on: redis.eventLoop).get()

        return zip(domains, results).map { (domain, fields) in
            let reason = fields["reason"]?.string
            let createdAt = fields["createdAt"]?.string.flatMap { parseDate($0) }
            return BlockedDomain(domain: domain, reason: reason, createdAt: createdAt)
        }
    }

    func blockDomain(_ domain: String, reason: String?) async throws -> Bool {
        let added = try await redis.sadd(domain, to: blockedDomainsSetKey).get()
        guard added > 0 else { return false }

        let now = formatDate(Date())
        var fields: [String: RESPValue] = [
            "createdAt": .init(from: now)
        ]
        if let reason {
            fields["reason"] = .init(from: reason)
        }
        _ = try await redis.hmset(fields, in: blockedDomainKey(domain)).get()
        return true
    }

    func unblockDomain(_ domain: String) async throws -> Bool {
        let removed = try await redis.srem(domain, from: blockedDomainsSetKey).get()
        guard removed > 0 else { return false }
        _ = try await redis.send(
            command: "DEL",
            with: [.init(from: blockedDomainKey(domain).rawValue)]
        ).get()
        return true
    }

    // MARK: - Allowed Domains

    func isAllowed(domain: String) async throws -> Bool {
        try await redis.sismember(domain, of: allowedDomainsSetKey).get()
    }

    // MARK: - Settings

    func getSetting(key: String) async throws -> String? {
        let value = try await redis.hget(key, from: settingsKey).get()
        return value.string
    }

    func setSetting(key: String, value: String) async throws {
        _ = try await redis.hset(key, to: value, in: settingsKey).get()
    }

    // MARK: - Decoding Helpers

    private func decodeSubscriber(domain: String, fields: [String: RESPValue]) -> Subscriber? {
        guard
            let inboxURL = fields["inboxURL"]?.string,
            let actorID = fields["actorID"]?.string,
            let stateRaw = fields["state"]?.string,
            let state = SubscriberState(rawValue: stateRaw),
            let followActivityID = fields["followActivityID"]?.string
        else {
            return nil
        }

        let followObjectURI = fields["followObjectURI"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let createdAt = fields["createdAt"]?.string.flatMap { parseDate($0) }
        let updatedAt = fields["updatedAt"]?.string.flatMap { parseDate($0) }

        return Subscriber(
            domain: domain,
            inboxURL: inboxURL,
            actorID: actorID,
            state: state,
            followActivityID: followActivityID,
            followObjectURI: followObjectURI,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

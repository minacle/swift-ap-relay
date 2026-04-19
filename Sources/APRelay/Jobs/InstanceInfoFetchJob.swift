import APRelayCore
import Foundation
import Queues
import Vapor

/// Payload identifying a single domain whose instance info should be fetched.
struct InstanceInfoFetchPayload: Codable, Sendable {
    let domain: String
}

/// Fetches and caches instance info for a single remote domain.
///
/// Dispatched by ``InstanceInfoCheckJob`` — one job per subscriber domain.
/// Queue worker count naturally limits concurrent outbound requests.
struct InstanceInfoFetchJob: AsyncJob {
    typealias Payload = InstanceInfoFetchPayload

    func dequeue(_ context: QueueContext, _ payload: InstanceInfoFetchPayload) async throws {
        let app = context.application
        let cache = app.instanceInfoCache
        let client = app.client

        let allowedPrivateAddresses = app.relayConfig.allowedPrivateAddresses
        let info = try await fetchInstanceInfo(domain: payload.domain, client: client, allowedPrivateAddresses: allowedPrivateAddresses)
        try await cache.setInstanceInfo(domain: payload.domain, info: info)
        context.logger.debug("Instance info check succeeded for \(payload.domain)")
    }

    func error(_ context: QueueContext, _ error: any Error, _ payload: InstanceInfoFetchPayload) async throws {
        let cache = context.application.instanceInfoCache
        let now = Date()

        // Preserve last-known metadata; flip reachability and accumulate backoff.
        let existing = try? await cache.getInstanceInfo(domain: payload.domain)
        let failures = (existing?.consecutiveFailures ?? 0) + 1
        let backoff = Self.exponentialBackoffSeconds(attempt: failures, base: 60, maxInterval: 30 * 60)
        let nextAttemptAt = now.addingTimeInterval(TimeInterval(backoff))

        let updated = InstanceInfo(
            softwareName: existing?.softwareName,
            softwareVersion: existing?.softwareVersion,
            openRegistrations: existing?.openRegistrations,
            staffAccounts: existing?.staffAccounts,
            faviconURL: existing?.faviconURL,
            isReachable: false,
            lastCheckedAt: now,
            consecutiveFailures: failures,
            nextAttemptAt: nextAttemptAt
        )
        try? await cache.setInstanceInfo(domain: payload.domain, info: updated)
        context.logger.warning("Instance info check failed for \(payload.domain) (failures=\(failures), nextAttemptAt=\(nextAttemptAt)): \(error)")
    }
}

// MARK: - Instance Info Fetching

private let nodeInfoSchemas = [
    "http://nodeinfo.diaspora.software/ns/schema/2.1",
    "http://nodeinfo.diaspora.software/ns/schema/2.0",
]

private func fetchInstanceInfo(domain: String, client: any Client, allowedPrivateAddresses: [String]) async throws -> InstanceInfo {
    // Step 1: Discover NodeInfo endpoint via well-known
    let wellKnownURL = URI(string: "https://\(domain)/.well-known/nodeinfo")
    let wellKnownResponse = try await client.get(wellKnownURL) { req in
        req.headers.add(name: .accept, value: "application/json")
    }

    guard wellKnownResponse.status == .ok else {
        throw InstanceInfoFetchError.wellKnownFailed(domain, wellKnownResponse.status)
    }

    let wellKnown = try wellKnownResponse.content.decode(NodeInfoWellKnown.self)

    // Step 2: Find the best NodeInfo link (prefer 2.1, then 2.0)
    guard let link = nodeInfoSchemas.lazy.compactMap({ schema in
        wellKnown.links.first { $0.rel == schema }
    }).first else {
        throw InstanceInfoFetchError.noSupportedSchema(domain)
    }

    // Step 3: Validate the NodeInfo URL before fetching
    try validateOutboundURL(link.href, allowedPrivateAddresses: allowedPrivateAddresses)

    // Step 4: Fetch the NodeInfo document
    let nodeInfoURL = URI(string: link.href)
    let nodeInfoResponse = try await client.get(nodeInfoURL) { req in
        req.headers.add(name: .accept, value: "application/json")
    }

    guard nodeInfoResponse.status == .ok else {
        throw InstanceInfoFetchError.nodeInfoFailed(domain, nodeInfoResponse.status)
    }

    let nodeInfo = try nodeInfoResponse.content.decode(NodeInfoResponse.self)

    let safeStaffAccounts = nodeInfo.metadata["staffAccounts"]?.array?
        .compactMap(\.string)
        .filter { uri in
            guard let colonIndex = uri.firstIndex(of: ":") else { return false }
            return allowedSchemes.contains(uri[..<colonIndex].lowercased())
        }

    // Step 5: Fetch favicon URL from the instance homepage
    let faviconURL = await fetchFaviconURL(domain: domain, client: client, allowedPrivateAddresses: allowedPrivateAddresses)

    return InstanceInfo(
        softwareName: nodeInfo.software.name,
        softwareVersion: nodeInfo.software.version,
        openRegistrations: nodeInfo.openRegistrations,
        staffAccounts: safeStaffAccounts,
        faviconURL: faviconURL,
        isReachable: true,
        lastCheckedAt: Date(),
        consecutiveFailures: 0,
        nextAttemptAt: nil
    )
}

// MARK: - Favicon Fetching

private func fetchFaviconURL(domain: String, client: any Client, allowedPrivateAddresses: [String]) async -> String? {
    do {
        let homepageURL = URI(string: "https://\(domain)/")
        try validateOutboundURL(homepageURL.string, allowedPrivateAddresses: allowedPrivateAddresses)

        let response = try await client.get(homepageURL) { req in
            req.headers.add(name: .accept, value: "text/html")
        }

        guard response.status == .ok else { return nil }

        let contentType = response.headers.first(name: .contentType) ?? ""
        guard contentType.contains("text/html") else { return nil }

        guard let body = response.body,
              let html = body.getString(at: body.readerIndex, length: min(body.readableBytes, 32_768))
        else { return nil }

        guard let baseURL = URL(string: "https://\(domain)/") else { return nil }
        guard let faviconURL = extractFaviconURL(fromHTML: html, baseURL: baseURL) else { return nil }

        // Validate the extracted favicon URL to prevent browser-side SSRF
        // (e.g. a malicious instance embedding a private IP as its favicon href).
        try validateOutboundURL(faviconURL, allowedPrivateAddresses: allowedPrivateAddresses)

        return faviconURL
    } catch {
        return nil
    }
}

// MARK: - Outbound URL Validation

enum OutboundURLValidationError: Error, CustomStringConvertible {
    case invalidURL(String)
    case disallowedScheme(String, scheme: String)
    case reservedHost(String, host: String)
    case privateAddress(String, host: String)

    var description: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid outbound URL: \(url)"
        case .disallowedScheme(let url, let scheme):
            return "Disallowed scheme '\(scheme)' in outbound URL: \(url)"
        case .reservedHost(let url, let host):
            return "Reserved host '\(host)' in outbound URL: \(url)"
        case .privateAddress(let url, let host):
            return "Private address '\(host)' in outbound URL: \(url)"
        }
    }
}

/// Validates that a URL is safe for outbound requests.
///
/// Checks:
/// 1. Scheme is `http` or `https`
/// 2. Host is not `localhost` or `.localhost`
/// 3. If host is an IP literal, it must not be in a private/reserved range
///    (unless explicitly allowed via `allowedPrivateAddresses`)
func validateOutboundURL(_ urlString: String, allowedPrivateAddresses: [String]) throws {
    guard let url = URL(string: urlString) else {
        throw OutboundURLValidationError.invalidURL(urlString)
    }

    let scheme = url.scheme?.lowercased() ?? ""
    guard scheme == "http" || scheme == "https" else {
        throw OutboundURLValidationError.disallowedScheme(urlString, scheme: scheme)
    }

    guard let host = url.host(), !host.isEmpty else {
        throw OutboundURLValidationError.invalidURL(urlString)
    }

    let lowerHost = host.lowercased()
    if lowerHost == "localhost" || lowerHost.hasSuffix(".localhost") {
        throw OutboundURLValidationError.reservedHost(urlString, host: host)
    }

    // Check IPv4 literal
    var addr4 = in_addr()
    if unsafe inet_pton(AF_INET, host, &addr4) == 1 {
        if isPrivateIPv4(addr4) && !isAddressAllowed(host, in: allowedPrivateAddresses) {
            throw OutboundURLValidationError.privateAddress(urlString, host: host)
        }
        return
    }

    // Check IPv6 literal (Foundation strips brackets from url.host())
    var addr6 = in6_addr()
    if unsafe inet_pton(AF_INET6, host, &addr6) == 1 {
        if isPrivateIPv6(addr6) && !isAddressAllowed(host, in: allowedPrivateAddresses) {
            throw OutboundURLValidationError.privateAddress(urlString, host: host)
        }
        return
    }

    // Host is a domain name — allow (no DNS resolution check)
}

// MARK: - Staff Account URI Filtering

private let allowedSchemes: Set<String> = [
    "https", "http", "mailto", "xmpp", "matrix", "tel",
]

private enum InstanceInfoFetchError: Error, CustomStringConvertible {
    case wellKnownFailed(String, HTTPResponseStatus)
    case noSupportedSchema(String)
    case nodeInfoFailed(String, HTTPResponseStatus)

    var description: String {
        switch self {
        case .wellKnownFailed(let domain, let status):
            return "Well-known fetch failed for \(domain): \(status)"
        case .noSupportedSchema(let domain):
            return "No supported NodeInfo schema for \(domain)"
        case .nodeInfoFailed(let domain, let status):
            return "NodeInfo fetch failed for \(domain): \(status)"
        }
    }
}

import APRelayCore
import Foundation
import Queues
import Vapor

/// Payload identifying a single domain whose NodeInfo should be fetched.
struct NodeInfoFetchPayload: Codable, Sendable {
    let domain: String
}

/// Fetches and caches NodeInfo for a single remote domain.
///
/// Dispatched by ``NodeInfoCheckJob`` — one job per subscriber domain.
/// Queue worker count naturally limits concurrent outbound requests.
struct NodeInfoFetchJob: AsyncJob {
    typealias Payload = NodeInfoFetchPayload

    func dequeue(_ context: QueueContext, _ payload: NodeInfoFetchPayload) async throws {
        let app = context.application
        let cache = app.nodeInfoCache
        let client = app.client

        let allowedPrivateAddresses = app.relayConfig.allowedPrivateAddresses
        let info = try await fetchNodeInfo(domain: payload.domain, client: client, allowedPrivateAddresses: allowedPrivateAddresses)
        try await cache.setNodeInfo(domain: payload.domain, info: info)
        context.logger.debug("NodeInfo check succeeded for \(payload.domain)")
    }

    func error(_ context: QueueContext, _ error: any Error, _ payload: NodeInfoFetchPayload) async throws {
        let cache = context.application.nodeInfoCache
        let failedInfo = RemoteNodeInfo(
            isReachable: false,
            lastCheckedAt: Date()
        )
        try? await cache.setNodeInfo(domain: payload.domain, info: failedInfo)
        context.logger.debug("NodeInfo check failed for \(payload.domain): \(error)")
    }
}

// MARK: - NodeInfo Fetching

private let nodeInfoSchemas = [
    "http://nodeinfo.diaspora.software/ns/schema/2.1",
    "http://nodeinfo.diaspora.software/ns/schema/2.0",
]

private func fetchNodeInfo(domain: String, client: any Client, allowedPrivateAddresses: [String]) async throws -> RemoteNodeInfo {
    // Step 1: Discover NodeInfo endpoint via well-known
    let wellKnownURL = URI(string: "https://\(domain)/.well-known/nodeinfo")
    let wellKnownResponse = try await client.get(wellKnownURL) { req in
        req.headers.add(name: .accept, value: "application/json")
    }

    guard wellKnownResponse.status == .ok else {
        throw NodeInfoFetchError.wellKnownFailed(wellKnownResponse.status)
    }

    let wellKnown = try wellKnownResponse.content.decode(NodeInfoWellKnown.self)

    // Step 2: Find the best NodeInfo link (prefer 2.1, then 2.0)
    guard let link = nodeInfoSchemas.lazy.compactMap({ schema in
        wellKnown.links.first { $0.rel == schema }
    }).first else {
        throw NodeInfoFetchError.noSupportedSchema
    }

    // Step 3: Validate the NodeInfo URL before fetching
    try validateOutboundURL(link.href, allowedPrivateAddresses: allowedPrivateAddresses)

    // Step 4: Fetch the NodeInfo document
    let nodeInfoURL = URI(string: link.href)
    let nodeInfoResponse = try await client.get(nodeInfoURL) { req in
        req.headers.add(name: .accept, value: "application/json")
    }

    guard nodeInfoResponse.status == .ok else {
        throw NodeInfoFetchError.nodeInfoFailed(nodeInfoResponse.status)
    }

    let nodeInfo = try nodeInfoResponse.content.decode(NodeInfoResponse.self)

    let safeStaffAccounts = nodeInfo.metadata?.staffAccounts?.filter { uri in
        guard let colonIndex = uri.firstIndex(of: ":") else { return false }
        return allowedSchemes.contains(uri[..<colonIndex].lowercased())
    }

    return RemoteNodeInfo(
        softwareName: nodeInfo.software.name,
        softwareVersion: nodeInfo.software.version,
        openRegistrations: nodeInfo.openRegistrations,
        staffAccounts: safeStaffAccounts,
        isReachable: true,
        lastCheckedAt: Date()
    )
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

private enum NodeInfoFetchError: Error {
    case wellKnownFailed(HTTPResponseStatus)
    case noSupportedSchema
    case nodeInfoFailed(HTTPResponseStatus)
}

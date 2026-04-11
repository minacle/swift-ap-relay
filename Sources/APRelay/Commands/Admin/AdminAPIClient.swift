import Vapor

/// Error type for Admin API client operations.
enum AdminAPIError: Error, CustomStringConvertible {
    case notConfigured
    case connectionFailed(url: String, detail: String)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case serverError(status: UInt, reason: String)

    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }

    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .notConfigured:
            return "ADMIN_TOKEN is not configured. Set the ADMIN_TOKEN environment variable."
        case .connectionFailed(let url, let detail):
            return "Could not connect to the relay server at \(url). Is the server running? (\(detail))"
        case .unauthorized(let reason):
            return "Authentication failed: \(reason)"
        case .forbidden(let reason):
            return "Access denied: \(reason)"
        case .notFound(let reason):
            return reason
        case .conflict(let reason):
            return reason
        case .serverError(let status, let reason):
            return "Server error (\(status)): \(reason)"
        }
    }
}

/// HTTP client for the Admin API.
///
/// Wraps Vapor's `Client` to call the relay server's admin endpoints,
/// constructing the base URL from `RelayConfiguration`.
struct AdminAPIClient: Sendable {
    private let client: any Client
    private let baseURL: String
    private let adminToken: String

    /// Creates an Admin API client with explicit parameters.
    ///
    /// - Parameters:
    ///   - client: The HTTP client to use for requests.
    ///   - baseURL: The base URL of the relay server (e.g. `http://localhost:8080`).
    ///   - adminToken: The bearer token for authentication.
    init(client: any Client, baseURL: String, adminToken: String) {
        self.client = client
        self.baseURL = baseURL
        self.adminToken = adminToken
    }

    /// Creates an Admin API client from the application context.
    ///
    /// - Parameter app: The Vapor application providing client and configuration.
    /// - Throws: `AdminAPIError.notConfigured` if `ADMIN_TOKEN` is empty.
    init(app: Application) throws {
        let config = app.relayConfig
        guard !config.adminToken.isEmpty else {
            throw AdminAPIError.notConfigured
        }
        self.init(
            client: app.client,
            baseURL: "\(config.scheme)://\(config.domain):\(config.port)",
            adminToken: config.adminToken
        )
    }

    // MARK: - Subscribers

    /// Lists subscribers, optionally filtered by state.
    func listSubscribers(state: String? = nil) async throws -> [Subscriber] {
        var url = "\(baseURL)/api/admin/subscribers"
        if let state {
            url += "?state=\(state)"
        }
        let response = try await performRequest(.GET, url: url)
        return try response.content.decode([Subscriber].self)
    }

    /// Accepts a pending subscriber.
    func acceptSubscriber(domain: String) async throws -> AdminResponse {
        let url = "\(baseURL)/api/admin/subscribers/\(domain.urlPathEncoded)/accept"
        let response = try await performRequest(.POST, url: url)
        return try response.content.decode(AdminResponse.self)
    }

    /// Rejects a pending subscriber.
    func rejectSubscriber(domain: String) async throws -> AdminResponse {
        let url = "\(baseURL)/api/admin/subscribers/\(domain.urlPathEncoded)/reject"
        let response = try await performRequest(.POST, url: url)
        return try response.content.decode(AdminResponse.self)
    }

    // MARK: - Blocked Domains

    /// Lists all blocked domains.
    func listBlockedDomains() async throws -> [BlockedDomain] {
        let url = "\(baseURL)/api/admin/blocked-domains"
        let response = try await performRequest(.GET, url: url)
        return try response.content.decode([BlockedDomain].self)
    }

    /// Blocks a domain with an optional reason.
    func blockDomain(_ domain: String, reason: String? = nil) async throws -> AdminResponse {
        let url = "\(baseURL)/api/admin/blocked-domains"
        let body = BlockRequest(domain: domain, reason: reason)
        let response = try await performRequest(.POST, url: url, content: body)
        return try response.content.decode(AdminResponse.self)
    }

    /// Unblocks a domain.
    func unblockDomain(_ domain: String) async throws -> AdminResponse {
        let url = "\(baseURL)/api/admin/blocked-domains/\(domain.urlPathEncoded)"
        let response = try await performRequest(.DELETE, url: url)
        return try response.content.decode(AdminResponse.self)
    }

    // MARK: - Private

    private var authHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: adminToken)
        return headers
    }

    private func performRequest(
        _ method: HTTPMethod,
        url: String
    ) async throws -> ClientResponse {
        let response: ClientResponse
        do {
            response = try await client.send(
                method,
                headers: authHeaders,
                to: URI(string: url)
            )
        } catch {
            throw AdminAPIError.connectionFailed(
                url: baseURL,
                detail: error.localizedDescription
            )
        }
        try validateResponse(response)
        return response
    }

    private func performRequest<T: Content>(
        _ method: HTTPMethod,
        url: String,
        content body: T
    ) async throws -> ClientResponse {
        let response: ClientResponse
        do {
            response = try await client.send(
                method,
                headers: authHeaders,
                to: URI(string: url)
            ) { req in
                try req.content.encode(body)
            }
        } catch {
            throw AdminAPIError.connectionFailed(
                url: baseURL,
                detail: error.localizedDescription
            )
        }
        try validateResponse(response)
        return response
    }

    private func validateResponse(_ response: ClientResponse) throws {
        guard response.status.code >= 200, response.status.code < 300 else {
            let reason = extractReason(from: response)
            switch response.status {
            case .unauthorized:
                throw AdminAPIError.unauthorized(reason)
            case .forbidden:
                throw AdminAPIError.forbidden(reason)
            case .notFound:
                throw AdminAPIError.notFound(reason)
            case .conflict:
                throw AdminAPIError.conflict(reason)
            default:
                throw AdminAPIError.serverError(
                    status: response.status.code,
                    reason: reason
                )
            }
        }
    }

    private func extractReason(from response: ClientResponse) -> String {
        if let errorResponse = try? response.content.decode(VaporErrorResponse.self) {
            return errorResponse.reason
        }
        return response.status.reasonPhrase
    }
}

// MARK: - Helpers

private struct VaporErrorResponse: Decodable {
    let error: Bool
    let reason: String
}

extension String {
    fileprivate var urlPathEncoded: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

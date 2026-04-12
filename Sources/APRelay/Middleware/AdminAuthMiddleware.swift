import Crypto
import Vapor

/// Middleware that validates the Bearer token for admin API endpoints.
struct AdminAuthMiddleware: AsyncMiddleware {
    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let config = request.relayConfig

        guard !config.adminToken.isEmpty else {
            throw Abort(.forbidden, reason: "Admin API not configured (ADMIN_TOKEN not set)")
        }

        guard let bearer = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing Authorization header")
        }

        // Constant-time comparison via HMAC: MessageAuthenticationCode's == is guaranteed constant-time.
        let fixedMessage = Data("admin-token-verify".utf8)
        let expectedMAC = HMAC<SHA256>.authenticationCode(
            for: fixedMessage,
            using: SymmetricKey(data: Data(config.adminToken.utf8))
        )
        let candidateMAC = HMAC<SHA256>.authenticationCode(
            for: fixedMessage,
            using: SymmetricKey(data: Data(bearer.token.utf8))
        )
        guard expectedMAC == candidateMAC else {
            throw Abort(.unauthorized, reason: "Invalid admin token")
        }

        return try await next.respond(to: request)
    }
}

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

        let tokenHash = SHA256.hash(data: Data(bearer.token.utf8))
        let expectedHash = SHA256.hash(data: Data(config.adminToken.utf8))
        guard tokenHash == expectedHash else {
            throw Abort(.unauthorized, reason: "Invalid admin token")
        }

        return try await next.respond(to: request)
    }
}

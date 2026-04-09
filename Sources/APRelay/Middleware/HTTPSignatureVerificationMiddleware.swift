import APRelayCore
import _CryptoExtras
import Vapor

/// Middleware that verifies HTTP signatures on incoming requests to the inbox.
struct HTTPSignatureVerificationMiddleware: AsyncMiddleware {
    private let httpSignature = HTTPSignature()

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        guard let signatureHeader = request.headers.first(name: "Signature") else {
            throw Abort(.unauthorized, reason: "Missing Signature header")
        }

        guard let components = httpSignature.parseSignatureHeader(signatureHeader) else {
            throw Abort(.badRequest, reason: "Invalid Signature header")
        }

        // Validate Date header if it is in the signed headers list.
        if components.headers.contains(where: { $0.lowercased() == "date" }) {
            guard let dateStr = request.headers.first(name: "Date") else {
                throw Abort(.unauthorized, reason: "Missing Date header")
            }
            guard let date = httpSignature.parseHTTPDate(dateStr) else {
                throw Abort(.unauthorized, reason: "Invalid Date header format")
            }
            let age = abs(Date().timeIntervalSince(date))
            if age > 43200 {
                throw Abort(.unauthorized, reason: "Request date too far from current time")
            }
        }

        // Validate Digest header matches body.
        let body = request.body.data ?? ByteBuffer()
        let bodyData = Data(buffer: body)

        if request.method == .POST {
            guard let digest = request.headers.first(name: "Digest") else {
                throw Abort(.unauthorized, reason: "Missing Digest header")
            }
            let expectedPrefix = "SHA-256="
            guard digest.hasPrefix(expectedPrefix) else {
                throw Abort(.unauthorized, reason: "Unsupported digest algorithm")
            }
            let expectedHash = String(digest.dropFirst(expectedPrefix.count))
            let actualHash = Data(Crypto.SHA256.hash(data: bodyData)).base64EncodedString()
            if expectedHash != actualHash {
                throw Abort(.unauthorized, reason: "Digest mismatch")
            }
        }

        // Fetch the remote actor's public key.
        let keyID = components.keyID
        let actorURL = resolveActorURL(from: keyID)

        let remoteActor = try await request.application.actorFetcher.fetchActor(
            url: actorURL,
            client: request.client
        )

        guard let publicKeyPEM = remoteActor.publicKey?.publicKeyPem else {
            throw Abort(.unauthorized, reason: "Remote actor has no public key")
        }

        // Verify the signature.
        let method = request.method.rawValue.lowercased()
        let path =
            request.url.path
            + (request.url.query.map { "?\($0)" } ?? "")

        // Convert Vapor HTTPHeaders to [String: String] for Core.
        var headerMap: [String: String] = [:]
        for (name, value) in request.headers {
            headerMap[name] = value
        }

        let isValid = try httpSignature.verify(
            method: method,
            path: path,
            requestHeaders: headerMap,
            body: bodyData,
            components: components,
            publicKeyPEM: publicKeyPEM
        )

        guard isValid else {
            throw Abort(.unauthorized, reason: "Invalid HTTP signature")
        }

        // Store verified actor info for downstream handlers.
        request.storage[VerifiedActorKey.self] = VerifiedActor(
            id: remoteActor.id,
            inbox: remoteActor.inbox,
            sharedInbox: remoteActor.sharedInbox,
            publicKeyPEM: publicKeyPEM
        )

        return try await next.respond(to: request)
    }

    /// Resolves the actor URL from a key ID.
    ///
    /// Handles fragment-based (`actor#main-key`) and path-based
    /// (`actor/publickey`) key ID formats.
    private func resolveActorURL(from keyID: String) -> String {
        // Fragment-based (Mastodon/Misskey: actor#main-key).
        if let hashIndex = keyID.firstIndex(of: "#") {
            return String(keyID.prefix(upTo: hashIndex))
        }

        // Path-based (Pleroma: actor/publickey, actor/main-key).
        let knownSuffixes = ["/publickey", "/main-key"]
        let lowered = keyID.lowercased()
        for suffix in knownSuffixes {
            if lowered.hasSuffix(suffix) {
                return String(keyID.dropLast(suffix.count))
            }
        }

        return keyID
    }

}

/// Verified actor information stored in request storage after signature verification.
struct VerifiedActor: Sendable {
    let id: String
    let inbox: String?
    let sharedInbox: String?
    let publicKeyPEM: String
}

struct VerifiedActorKey: StorageKey {
    typealias Value = VerifiedActor
}

extension Request {
    var verifiedActor: VerifiedActor? {
        storage[VerifiedActorKey.self]
    }
}

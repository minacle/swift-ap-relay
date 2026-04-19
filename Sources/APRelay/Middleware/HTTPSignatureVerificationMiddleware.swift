import APRelayCore
import Crypto
import _CryptoExtras
import Vapor

/// Middleware that verifies HTTP signatures on incoming requests to the inbox.
struct HTTPSignatureVerificationMiddleware: AsyncMiddleware {
    private let httpSignature = HTTPSignature()

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // Error responses are deliberately uniform — a single `Signature verification failed`
        // with 401 for every failure mode, so error shape cannot be used as an oracle
        // to fingerprint which verification step a probe reached. Details are logged
        // server-side only.
        guard let signatureHeader = request.headers.first(name: "Signature") else {
            request.logger.warning("Signature verification failed: missing Signature header")
            throw Self.genericFailure
        }

        guard let components = httpSignature.parseSignatureHeader(signatureHeader) else {
            request.logger.warning("Signature verification failed: malformed Signature header")
            throw Self.genericFailure
        }

        // Validate Date header if it is in the signed headers list.
        if components.headers.contains(where: { $0.lowercased() == "date" }) {
            guard let dateStr = request.headers.first(name: "Date") else {
                request.logger.warning("Signature verification failed: missing Date header")
                throw Self.genericFailure
            }
            guard let date = httpSignature.parseHTTPDate(dateStr) else {
                request.logger.warning("Signature verification failed: invalid Date header format")
                throw Self.genericFailure
            }
            let age = abs(Date().timeIntervalSince(date))
            if age > 43200 {
                request.logger.warning("Signature verification failed: Date header outside 12h window (age=\(Int(age))s)")
                throw Self.genericFailure
            }
        }

        // Collect the body from the stream. Middleware runs before Vapor's
        // route-level body collection, so request.body.data is nil for
        // streamed requests.
        let bodyBuffer = try await request.body.collect(
            max: request.application.routes.defaultMaxBodySize.value
        ).get() ?? ByteBuffer()

        if request.method == .POST {
            guard let digest = request.headers.first(name: "Digest") else {
                request.logger.warning("Signature verification failed: missing Digest header on POST")
                throw Self.genericFailure
            }
            let expectedPrefix = "SHA-256="
            guard digest.hasPrefix(expectedPrefix) else {
                request.logger.warning("Signature verification failed: unsupported digest algorithm in Digest header")
                throw Self.genericFailure
            }
            let expectedHash = String(digest.dropFirst(expectedPrefix.count))
            let actualHash = Data(SHA256.hash(data: bodyBuffer.readableBytesView)).base64EncodedString()
            if expectedHash != actualHash {
                request.logger.warning("Signature verification failed: Digest mismatch")
                throw Self.genericFailure
            }
        }

        // Fetch the remote actor's public key.
        let keyID = components.keyID
        let actorURL = resolveActorURL(from: keyID)

        let remoteActor: RemoteActor
        do {
            remoteActor = try await request.application.actorFetcher.fetchActor(
                url: actorURL,
                client: request.client
            )
        } catch {
            // Mask the underlying error (which may include the attacker-controlled
            // actor URL) so that an unauthenticated caller cannot use error responses
            // to confirm that the server reached a particular outbound URL.
            request.logger.warning("Signature verification failed: actor fetch error for keyID=\(keyID): \(error)")
            throw Self.genericFailure
        }

        guard let publicKeyPEM = remoteActor.publicKey?.publicKeyPem else {
            request.logger.warning("Signature verification failed: remote actor \(remoteActor.id) has no public key")
            throw Self.genericFailure
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

        let isValid: Bool
        do {
            isValid = try httpSignature.verify(
                method: method,
                path: path,
                requestHeaders: headerMap,
                components: components,
                publicKeyPEM: publicKeyPEM
            )
        } catch {
            request.logger.warning("Signature verification failed: verify threw for keyID=\(keyID): \(error)")
            throw Self.genericFailure
        }

        guard isValid else {
            request.logger.warning("Signature verification failed: signature invalid for keyID=\(keyID)")
            throw Self.genericFailure
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

    private static let genericFailure = Abort(.unauthorized, reason: "Signature verification failed")

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

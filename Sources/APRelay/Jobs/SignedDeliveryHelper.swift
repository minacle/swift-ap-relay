import APRelayCore
import _CryptoExtras
import Foundation
import Metrics
import Tracing
import Vapor

/// Shared helper for sending HTTP-signature-signed ActivityPub requests.
enum SignedDeliveryHelper {
    private static let httpSignature = HTTPSignature()

    /// Sends a signed HTTP POST of the given body to a remote inbox.
    static func send(
        activity: Data,
        to inboxURL: String,
        config: RelayConfiguration,
        privateKey: _RSA.Signing.PrivateKey,
        client: any Client,
        logger: Logger
    ) async throws {
        guard let url = URL(string: inboxURL) else {
            throw DeliveryError.invalidURL(inboxURL)
        }

        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let host = url.host() ?? ""
        let keyID = "\(config.actorURL)#main-key"

        let headers = try httpSignature.sign(
            method: "post",
            path: path,
            host: host,
            body: activity,
            privateKey: privateKey,
            keyID: keyID
        )

        let uri = URI(string: inboxURL)
        let response = try await client.post(uri) { req in
            for (name, value) in headers {
                req.headers.replaceOrAdd(name: name, value: value)
            }
            req.body = ByteBuffer(data: activity)
        }

        guard (200...299).contains(response.status.code) else {
            throw DeliveryError.httpError(response.status.code, inboxURL)
        }
    }
}

// MARK: - DeliveryError

enum DeliveryError: Error {
    case invalidURL(String)
    case httpError(UInt, String)

    var isRetryable: Bool {
        switch self {
        case .invalidURL:
            return false
        case .httpError(let code, _):
            if (400...499).contains(code) {
                return [401, 408, 429].contains(code)
            }
            return true
        }
    }
}

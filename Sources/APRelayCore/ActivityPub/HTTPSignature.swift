import Crypto
import _CryptoExtras
import Foundation

/// HTTP Signature implementation based on draft-cavage-http-signatures-06.
public struct HTTPSignature: Sendable {
    /// Headers to include when signing outgoing requests.
    public let signedHeaders = [
        "(request-target)", "host", "date", "digest", "content-type",
    ]

    public init() {}

    // MARK: - Signing

    /// Signs an outgoing HTTP request and returns the headers to attach as key-value pairs.
    public func sign(
        method: String,
        path: String,
        host: String,
        body: Data,
        privateKey: _RSA.Signing.PrivateKey,
        keyID: String
    ) throws -> [String: String] {
        let date = formatHTTPDate(Date())
        let digest = "SHA-256=\(Data(SHA256.hash(data: body)).base64EncodedString())"
        let contentType = "application/activity+json"

        let signingString = buildSigningString(
            method: method.lowercased(),
            path: path,
            headers: [
                "host": host,
                "date": date,
                "digest": digest,
                "content-type": contentType,
            ]
        )

        let signatureData = try privateKey.signature(
            for: Data(signingString.utf8),
            padding: .insecurePKCS1v1_5
        )
        let signatureBase64 = signatureData.rawRepresentation.base64EncodedString()

        let headersList = signedHeaders.joined(separator: " ")
        let signatureHeader =
            "keyId=\"\(keyID)\","
            + "algorithm=\"rsa-sha256\","
            + "headers=\"\(headersList)\","
            + "signature=\"\(signatureBase64)\""

        return [
            "Host": host,
            "Date": date,
            "Digest": digest,
            "Content-Type": contentType,
            "Signature": signatureHeader,
        ]
    }

    // MARK: - GET Signing

    /// Signs an outgoing HTTP GET request and returns the headers to attach.
    ///
    /// GET requests have no body, so `Digest` and `Content-Type` are omitted
    /// from the signed headers. Only `(request-target)`, `host`, and `date`
    /// are signed, matching the convention used by Mastodon, Misskey, and Pleroma.
    public func signGET(
        path: String,
        host: String,
        privateKey: _RSA.Signing.PrivateKey,
        keyID: String
    ) throws -> [String: String] {
        let date = formatHTTPDate(Date())
        let getSignedHeaders = ["(request-target)", "host", "date"]

        let signingString = buildSigningString(
            method: "get",
            path: path,
            headerNames: getSignedHeaders,
            headers: [
                "host": host,
                "date": date,
            ]
        )

        let signatureData = try privateKey.signature(
            for: Data(signingString.utf8),
            padding: .insecurePKCS1v1_5
        )
        let signatureBase64 = signatureData.rawRepresentation.base64EncodedString()

        let headersList = getSignedHeaders.joined(separator: " ")
        let signatureHeader =
            "keyId=\"\(keyID)\","
            + "algorithm=\"rsa-sha256\","
            + "headers=\"\(headersList)\","
            + "signature=\"\(signatureBase64)\""

        return [
            "Host": host,
            "Date": date,
            "Signature": signatureHeader,
        ]
    }

    // MARK: - Verification

    /// Parses a `Signature` header and returns its components.
    public func parseSignatureHeader(_ header: String) -> SignatureComponents? {
        var keyID: String?
        var headers: [String]?
        var signature: String?
        var algorithm: String?

        for part in header.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqIndex]
                var value = String(trimmed[trimmed.index(after: eqIndex)...])
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                switch key {
                case "keyId":
                    keyID = value
                case "headers":
                    headers = value.split(separator: " ").map(String.init)
                case "signature":
                    signature = value
                case "algorithm":
                    algorithm = value
                default:
                    break
                }
            }
        }

        guard let keyID, let headers, let signature else {
            return nil
        }

        return SignatureComponents(
            keyID: keyID,
            headers: headers,
            signature: signature,
            algorithm: algorithm ?? "rsa-sha256"
        )
    }

    /// Verifies an incoming request signature against the provided public key PEM.
    ///
    /// - Parameter requestHeaders: Header name-value pairs (case-insensitive lookup performed internally).
    public func verify(
        method: String,
        path: String,
        requestHeaders: [String: String],
        body: Data,
        components: SignatureComponents,
        publicKeyPEM: String
    ) throws(SignatureError) -> Bool {
        var headerMap: [String: String] = [:]
        for name in components.headers where name != "(request-target)" {
            // Case-insensitive header lookup.
            let lowered = name.lowercased()
            let value = requestHeaders.first { $0.key.lowercased() == lowered }?.value
            if let value {
                headerMap[lowered] = value
            }
        }

        let signingString = buildSigningString(
            method: method.lowercased(),
            path: path,
            headerNames: components.headers,
            headers: headerMap
        )

        guard let signatureData = Data(base64Encoded: components.signature) else {
            throw .invalidBase64
        }

        do {
            let publicKey = try _RSA.Signing.PublicKey(pemRepresentation: publicKeyPEM)
            let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: signatureData)

            return publicKey.isValidSignature(
                rsaSignature,
                for: Data(signingString.utf8),
                padding: .insecurePKCS1v1_5
            )
        } catch {
            throw .invalidPublicKey
        }
    }

    // MARK: - HTTP Date Formatting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    public func formatHTTPDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    public func parseHTTPDate(_ string: String) -> Date? {
        Self.dateFormatter.date(from: string)
    }

    // MARK: - Private

    private func buildSigningString(
        method: String,
        path: String,
        headers: [String: String]
    ) -> String {
        buildSigningString(
            method: method,
            path: path,
            headerNames: signedHeaders,
            headers: headers
        )
    }

    private func buildSigningString(
        method: String,
        path: String,
        headerNames: [String],
        headers: [String: String]
    ) -> String {
        headerNames.map { name in
            if name == "(request-target)" {
                "(request-target): \(method) \(path)"
            } else {
                "\(name): \(headers[name.lowercased()] ?? "")"
            }
        }.joined(separator: "\n")
    }
}

/// Errors that can occur during HTTP signature verification.
public enum SignatureError: Error {
    case invalidBase64
    case invalidPublicKey
}

/// Parsed HTTP Signature header components.
public struct SignatureComponents: Sendable {
    public let keyID: String
    public let headers: [String]
    public let signature: String
    public let algorithm: String

    public init(keyID: String, headers: [String], signature: String, algorithm: String) {
        self.keyID = keyID
        self.headers = headers
        self.signature = signature
        self.algorithm = algorithm
    }
}

import APRelayCore
import Crypto
import _CryptoExtras
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import APRelay

@Suite("Signature Middleware Tests", .serialized)
struct SignatureMiddlewareTests {
    @Test("Valid signature passes through")
    func validSignature() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }
        }
    }

    @Test("Missing Signature header returns 401")
    func missingSignature() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let data = try JSONEncoder().encode(activity)
            let digest = "SHA-256=\(Data(SHA256.hash(data: data)).base64EncodedString())"

            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/activity+json")
            headers.add(name: "Digest", value: digest)

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: ByteBuffer(data: data)
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Invalid signature (wrong key) returns 401")
    func wrongKey() async throws {
        try await withApp(configure: testConfigure) { app in
            // Sign with a different key than what the mock fetcher returns.
            let otherKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
            let activity = TestSigning.makeFollowActivity()
            let data = try JSONEncoder().encode(activity)

            let sigHeaders = try HTTPSignature().sign(
                method: "post",
                path: "/inbox",
                host: "localhost",
                body: data,
                privateKey: otherKey,
                keyID: "\(TestSigning.testActorID)#main-key"
            )

            var headers = HTTPHeaders()
            for (name, value) in sigHeaders {
                headers.add(name: name, value: value)
            }

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: ByteBuffer(data: data)
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Digest mismatch returns 401")
    func digestMismatch() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let (headers, _) = try TestSigning.signedRequest(activity: activity)

            // Send with a different body than what was signed.
            let tamperedBody = ByteBuffer(string: "{\"type\":\"tampered\"}")
            // Keep the original headers (with the original Digest), but change body.
            // The Digest won't match the tampered body.

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: tamperedBody
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Date too far in the past returns 401")
    func dateTooOld() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let data = try JSONEncoder().encode(activity)

            // Build headers manually with an old date.
            let httpSig = HTTPSignature()
            let oldDate = Date().addingTimeInterval(-86400)  // 24 hours ago
            let dateStr = httpSig.formatHTTPDate(oldDate)
            let digest = "SHA-256=\(Data(SHA256.hash(data: data)).base64EncodedString())"
            let contentType = "application/activity+json"
            let host = "localhost"

            let signingString = [
                "(request-target): post /inbox",
                "host: \(host)",
                "date: \(dateStr)",
                "digest: \(digest)",
                "content-type: \(contentType)",
            ].joined(separator: "\n")

            let signature = try TestSigning.privateKey.signature(
                for: Data(signingString.utf8),
                padding: .insecurePKCS1v1_5
            )
            let sigBase64 = signature.rawRepresentation.base64EncodedString()

            let sigHeader =
                "keyId=\"\(TestSigning.testActorID)#main-key\","
                + "algorithm=\"rsa-sha256\","
                + "headers=\"(request-target) host date digest content-type\","
                + "signature=\"\(sigBase64)\""

            var headers = HTTPHeaders()
            headers.add(name: "Host", value: host)
            headers.add(name: "Date", value: dateStr)
            headers.add(name: "Digest", value: digest)
            headers.add(name: "Content-Type", value: contentType)
            headers.add(name: "Signature", value: sigHeader)

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: ByteBuffer(data: data)
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Missing Digest header on POST returns 401")
    func missingDigest() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let data = try JSONEncoder().encode(activity)

            let httpSig = HTTPSignature()
            let dateStr = httpSig.formatHTTPDate(Date())
            let host = "localhost"

            // Sign without digest in headers list.
            let signingString = [
                "(request-target): post /inbox",
                "host: \(host)",
                "date: \(dateStr)",
            ].joined(separator: "\n")

            let signature = try TestSigning.privateKey.signature(
                for: Data(signingString.utf8),
                padding: .insecurePKCS1v1_5
            )
            let sigBase64 = signature.rawRepresentation.base64EncodedString()

            let sigHeader =
                "keyId=\"\(TestSigning.testActorID)#main-key\","
                + "algorithm=\"rsa-sha256\","
                + "headers=\"(request-target) host date\","
                + "signature=\"\(sigBase64)\""

            var headers = HTTPHeaders()
            headers.add(name: "Host", value: host)
            headers.add(name: "Date", value: dateStr)
            headers.add(name: "Content-Type", value: "application/activity+json")
            headers.add(name: "Signature", value: sigHeader)
            // No Digest header!

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: ByteBuffer(data: data)
            ) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }
}

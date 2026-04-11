import Foundation
import Testing
@testable import APRelayCore

@Suite("APContext Tests")
struct APContextTests {
    @Test("Default context includes ActivityStreams and Security")
    func defaultContext() throws {
        let context = APContext.default
        guard case .array(let values) = context else {
            Issue.record("Expected array context")
            return
        }
        #expect(values.contains("https://www.w3.org/ns/activitystreams"))
        #expect(values.contains("https://w3id.org/security/v1"))
    }

    @Test("Context encodes single string")
    func singleContext() throws {
        let context = APContext.single("https://www.w3.org/ns/activitystreams")
        let data = try JSONEncoder().encode(context)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("activitystreams"))
        #expect(!json.contains("["))
    }

    @Test("Context decodes array")
    func arrayContextDecode() throws {
        let json = "[\"https://www.w3.org/ns/activitystreams\", \"https://w3id.org/security/v1\"]"
        let context = try JSONDecoder().decode(APContext.self, from: Data(json.utf8))
        guard case .array(let values) = context else {
            Issue.record("Expected array context")
            return
        }
        #expect(values.count == 2)
    }

    @Test("Context decodes Pleroma-style mixed array with objects")
    func mixedArrayContextDecode() throws {
        let json = """
            ["https://www.w3.org/ns/activitystreams", {"@language": "und"}]
            """
        let context = try JSONDecoder().decode(APContext.self, from: Data(json.utf8))
        guard case .single(let value) = context else {
            Issue.record("Expected single context (one string extracted)")
            return
        }
        #expect(value == "https://www.w3.org/ns/activitystreams")
    }

    @Test("Context decodes mixed array with multiple strings and objects")
    func mixedArrayMultipleStrings() throws {
        let json = """
            [
                "https://www.w3.org/ns/activitystreams",
                "https://w3id.org/security/v1",
                {"@language": "und"}
            ]
            """
        let context = try JSONDecoder().decode(APContext.self, from: Data(json.utf8))
        guard case .array(let values) = context else {
            Issue.record("Expected array context")
            return
        }
        #expect(values.count == 2)
        #expect(values.contains("https://www.w3.org/ns/activitystreams"))
        #expect(values.contains("https://w3id.org/security/v1"))
    }
}

@Suite("APActivity Tests")
struct APActivityTests {
    @Test("Decode Follow activity")
    func decodeFollow() throws {
        let json = """
            {
                "@context": "https://www.w3.org/ns/activitystreams",
                "id": "https://mastodon.example/follow/1",
                "type": "Follow",
                "actor": "https://mastodon.example/actor",
                "object": "https://www.w3.org/ns/activitystreams#Public"
            }
            """
        let activity = try JSONDecoder().decode(APActivity.self, from: Data(json.utf8))
        #expect(activity.type == "Follow")
        #expect(activity.actor == "https://mastodon.example/actor")
        guard case .uri(let uri) = activity.object else {
            Issue.record("Expected URI object")
            return
        }
        #expect(uri == "https://www.w3.org/ns/activitystreams#Public")
    }

    @Test("Decode Undo with nested Follow")
    func decodeUndo() throws {
        let json = """
            {
                "@context": "https://www.w3.org/ns/activitystreams",
                "id": "https://mastodon.example/undo/1",
                "type": "Undo",
                "actor": "https://mastodon.example/actor",
                "object": {
                    "id": "https://mastodon.example/follow/1",
                    "type": "Follow",
                    "actor": "https://mastodon.example/actor",
                    "object": "https://www.w3.org/ns/activitystreams#Public"
                }
            }
            """
        let activity = try JSONDecoder().decode(APActivity.self, from: Data(json.utf8))
        #expect(activity.type == "Undo")
        guard case .activity(let inner) = activity.object else {
            Issue.record("Expected nested activity")
            return
        }
        #expect(inner.type == "Follow")
    }

    @Test("Decode activity with actor as object")
    func decodeActorAsObject() throws {
        let json = """
            {
                "@context": "https://www.w3.org/ns/activitystreams",
                "id": "https://example.com/activities/1",
                "type": "Create",
                "actor": {
                    "id": "https://example.com/users/1",
                    "type": "Person"
                },
                "object": "https://example.com/notes/1"
            }
            """
        let activity = try JSONDecoder().decode(APActivity.self, from: Data(json.utf8))
        #expect(activity.actor == "https://example.com/users/1")
        #expect(activity.type == "Create")
    }

    @Test("Encode Accept activity")
    func encodeAccept() throws {
        let accept = APActivity(
            context: .default,
            id: "https://relay.example/activities/123",
            type: "Accept",
            actor: "https://relay.example/actor",
            object: .activity(APActivity(
                context: nil,
                id: "https://mastodon.example/follow/1",
                type: "Follow",
                actor: "https://mastodon.example/actor",
                object: .uri("https://www.w3.org/ns/activitystreams#Public"),
                to: nil,
                cc: nil,
                published: nil
            )),
            to: nil,
            cc: nil,
            published: nil
        )

        let data = try JSONEncoder().encode(accept)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("Accept"))
        #expect(json.contains("Follow"))
    }
}

@Suite("APStringOrArray Tests")
struct APStringOrArrayTests {
    @Test("Public URI detection")
    func publicURI() {
        let single = APStringOrArray.single("https://www.w3.org/ns/activitystreams#Public")
        #expect(single.isPublic)

        let array = APStringOrArray.array(["as:Public", "https://example.com"])
        #expect(array.isPublic)

        let nonPublic = APStringOrArray.single("https://example.com")
        #expect(!nonPublic.isPublic)
    }
}

@Suite("HTTP Signature Tests")
struct HTTPSignatureTests {
    private let httpSignature = HTTPSignature()

    @Test("Parse signature header")
    func parseHeader() {
        let header = """
            keyId="https://relay.example/actor#main-key",\
            algorithm="rsa-sha256",\
            headers="(request-target) host date digest content-type",\
            signature="abc123=="
            """
        let components = httpSignature.parseSignatureHeader(header)
        #expect(components != nil)
        #expect(components?.keyID == "https://relay.example/actor#main-key")
        #expect(components?.algorithm == "rsa-sha256")
        #expect(components?.headers.count == 5)
        #expect(components?.signature == "abc123==")
    }

    @Test("Parse malformed header returns nil")
    func parseMalformed() {
        let components = httpSignature.parseSignatureHeader("not a valid header")
        #expect(components == nil)
    }
}

@Suite("HTTP Date Formatter Tests")
struct HTTPDateFormatterTests {
    private let httpSignature = HTTPSignature()

    @Test("Format and parse round-trip")
    func roundTrip() {
        let date = Date()
        let formatted = httpSignature.formatHTTPDate(date)
        let parsed = httpSignature.parseHTTPDate(formatted)
        #expect(parsed != nil)
        #expect(abs(date.timeIntervalSince(parsed!)) < 1.0)
    }

    @Test("Parse RFC 7231 date")
    func parseRFC7231() {
        let dateStr = "Wed, 09 Apr 2026 12:00:00 GMT"
        let date = httpSignature.parseHTTPDate(dateStr)
        #expect(date != nil)
    }
}

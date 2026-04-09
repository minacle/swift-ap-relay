import APRelayCore
import Fluent
import Testing
import Vapor
import VaporTesting
@testable import APRelay

@Suite("Inbox Tests", .serialized)
struct InboxTests {
    // MARK: - Follow

    @Test("Follow with public collection object creates accepted subscriber")
    func followMastodonStyle() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let subscribers = try await Subscriber.query(on: app.db).all()
            #expect(subscribers.count == 1)
            #expect(subscribers.first?.domain == TestSigning.testActorDomain)
            #expect(subscribers.first?.state == .accepted)
            #expect(
                subscribers.first?.followObjectURI
                    == "https://www.w3.org/ns/activitystreams#Public"
            )
        }
    }

    @Test("Follow with relay actor URL as object creates subscriber (Pleroma style)")
    func followPleromaStyle() async throws {
        try await withApp(configure: testConfigure) { app in
            let config = app.relayConfig
            let activity = TestSigning.makeFollowActivity(objectURI: config.actorURL)
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let subscribers = try await Subscriber.query(on: app.db).all()
            #expect(subscribers.count == 1)
            #expect(subscribers.first?.state == .accepted)
            #expect(subscribers.first?.followObjectURI == config.actorURL)
        }
    }

    @Test("Follow with unrecognized object is ignored")
    func followUnrecognizedObject() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeFollowActivity(
                objectURI: "https://unknown.example/something"
            )
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let count = try await Subscriber.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    @Test("Follow with manual accept creates pending subscriber")
    func followManualAccept() async throws {
        try await withApp(configure: testConfigureManualAccept) { app in
            let activity = TestSigning.makeFollowActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let subscriber = try await Subscriber.query(on: app.db).first()
            #expect(subscriber?.state == .pending)
        }
    }

    // MARK: - Undo

    @Test("Undo with nested Follow deletes subscriber")
    func undoNestedFollow() async throws {
        try await withApp(configure: testConfigure) { app in
            // Create subscriber first.
            let sub = Subscriber(
                domain: TestSigning.testActorDomain,
                inboxURL: TestSigning.testInboxURL,
                actorID: TestSigning.testActorID,
                state: .accepted,
                followActivityID: "https://remote.example/activities/follow-1"
            )
            try await sub.save(on: app.db)

            let activity = TestSigning.makeUndoActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let count = try await Subscriber.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    @Test("Undo with URI-only object deletes subscriber")
    func undoURIObject() async throws {
        try await withApp(configure: testConfigure) { app in
            let followID = "https://remote.example/activities/follow-1"
            let sub = Subscriber(
                domain: TestSigning.testActorDomain,
                inboxURL: TestSigning.testInboxURL,
                actorID: TestSigning.testActorID,
                state: .accepted,
                followActivityID: followID
            )
            try await sub.save(on: app.db)

            let activity = TestSigning.makeUndoActivity(objectAsURI: true)
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }

            let count = try await Subscriber.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    // MARK: - Create / Relay

    @Test("Create from accepted subscriber returns 202")
    func createFromSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: TestSigning.testActorDomain,
                inboxURL: TestSigning.testInboxURL,
                actorID: TestSigning.testActorID,
                state: .accepted,
                followActivityID: "https://remote.example/activities/follow-1"
            )
            try await sub.save(on: app.db)

            let activity = TestSigning.makeCreateActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }
        }
    }

    @Test("Create from non-subscriber is ignored")
    func createFromNonSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = TestSigning.makeCreateActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }
        }
    }

    // MARK: - Delete / Forward

    @Test("Delete from subscriber returns 202")
    func deleteFromSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: TestSigning.testActorDomain,
                inboxURL: TestSigning.testInboxURL,
                actorID: TestSigning.testActorID,
                state: .accepted,
                followActivityID: "https://remote.example/activities/follow-1"
            )
            try await sub.save(on: app.db)

            let activity = TestSigning.makeDeleteActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }
        }
    }

    // MARK: - Duplicate Detection

    @Test("Duplicate activity ID returns 202")
    func duplicateActivity() async throws {
        try await withApp(configure: testConfigure) { app in
            let activityID = "https://remote.example/activities/\(UUID().uuidString)"
            let activity1 = TestSigning.makeFollowActivity(id: activityID)
            let (headers1, body1) = try TestSigning.signedRequest(activity: activity1)

            try await app.testing().test(.POST, "inbox", headers: headers1, body: body1) {
                res async in
                #expect(res.status == .accepted)
            }

            // Second request with the same activity ID.
            let activity2 = TestSigning.makeFollowActivity(id: activityID)
            let (headers2, body2) = try TestSigning.signedRequest(activity: activity2)

            try await app.testing().test(.POST, "inbox", headers: headers2, body: body2) {
                res async in
                #expect(res.status == .accepted)
            }

            // Only one subscriber should exist.
            let count = try await Subscriber.query(on: app.db).count()
            #expect(count == 1)
        }
    }

    // MARK: - Domain Blocking

    @Test("Activity from blocked domain returns 403")
    func blockedDomain() async throws {
        try await withApp(configure: testConfigure) { app in
            let blocked = BlockedDomain(
                domain: TestSigning.testActorDomain,
                reason: "test"
            )
            try await blocked.save(on: app.db)

            let activity = TestSigning.makeFollowActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .forbidden)
            }
        }
    }

    // MARK: - Restricted Mode

    @Test("Activity from non-allowed domain in restricted mode returns 403")
    func restrictedModeBlocked() async throws {
        try await withApp(configure: testConfigureRestricted) { app in
            let activity = TestSigning.makeFollowActivity()
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .forbidden)
            }
        }
    }

    // MARK: - Invalid Input

    @Test("Invalid JSON body returns 400")
    func invalidJSON() async throws {
        try await withApp(configure: testConfigure) { app in
            let body = Data("not json".utf8)
            let sigHeaders = TestSigning.signedHeaders(body: body)
            var headers = HTTPHeaders()
            for (name, value) in sigHeaders {
                headers.add(name: name, value: value)
            }

            try await app.testing().test(
                .POST,
                "inbox",
                headers: headers,
                body: ByteBuffer(data: body)
            ) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test("Unknown activity type returns 202")
    func unknownActivityType() async throws {
        try await withApp(configure: testConfigure) { app in
            let activity = APActivity(
                context: .default,
                id: "https://remote.example/activities/\(UUID().uuidString)",
                type: "Like",
                actor: TestSigning.testActorID,
                object: .uri("https://remote.example/notes/1"),
                to: nil,
                cc: nil,
                published: nil
            )
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .accepted)
            }
        }
    }

    // MARK: - Actor-Signer Validation

    @Test("Activity with mismatched actor domain returns 403")
    func actorSignerMismatch() async throws {
        try await withApp(configure: testConfigure) { app in
            // Activity claims to be from evil.example but signed by remote.example.
            let activity = TestSigning.makeFollowActivity(
                actor: "https://evil.example/actor"
            )
            let (headers, body) = try TestSigning.signedRequest(activity: activity)

            try await app.testing().test(.POST, "inbox", headers: headers, body: body) {
                res async in
                #expect(res.status == .forbidden)
            }
        }
    }
}

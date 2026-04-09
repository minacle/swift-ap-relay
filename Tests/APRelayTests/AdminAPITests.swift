import Fluent
import Testing
import Vapor
import VaporTesting
@testable import APRelay

@Suite("Admin API Tests", .serialized)
struct AdminAPITests {
    private let authHeaders: HTTPHeaders = {
        var h = HTTPHeaders()
        h.bearerAuthorization = .init(token: "test-token")
        return h
    }()

    // MARK: - Subscribers

    @Test("GET /api/admin/subscribers returns empty list")
    func listSubscribersEmpty() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(
                .GET,
                "api/admin/subscribers",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "[]")
            }
        }
    }

    @Test("GET /api/admin/subscribers returns subscribers")
    func listSubscribers() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: "example.com",
                inboxURL: "https://example.com/inbox",
                actorID: "https://example.com/actor",
                state: .accepted,
                followActivityID: "https://example.com/follow/1"
            )
            try await sub.save(on: app.db)

            try await app.testing().test(
                .GET,
                "api/admin/subscribers",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("example.com"))
            }
        }
    }

    @Test("GET /api/admin/subscribers filters by state")
    func listSubscribersFilterState() async throws {
        try await withApp(configure: testConfigure) { app in
            let accepted = Subscriber(
                domain: "accepted.example",
                inboxURL: "https://accepted.example/inbox",
                actorID: "https://accepted.example/actor",
                state: .accepted,
                followActivityID: "https://accepted.example/follow/1"
            )
            let pending = Subscriber(
                domain: "pending.example",
                inboxURL: "https://pending.example/inbox",
                actorID: "https://pending.example/actor",
                state: .pending,
                followActivityID: "https://pending.example/follow/1"
            )
            try await accepted.save(on: app.db)
            try await pending.save(on: app.db)

            try await app.testing().test(
                .GET,
                "api/admin/subscribers?state=pending",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("pending.example"))
                #expect(!body.contains("accepted.example"))
            }
        }
    }

    @Test("POST accept changes state to accepted")
    func acceptSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: "test.example",
                inboxURL: "https://test.example/inbox",
                actorID: "https://test.example/actor",
                state: .pending,
                followActivityID: "https://test.example/follow/1"
            )
            try await sub.save(on: app.db)

            try await app.testing().test(
                .POST,
                "api/admin/subscribers/test.example/accept",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("accepted"))
            }

            let updated = try await Subscriber.query(on: app.db)
                .filter(\.$domain == "test.example")
                .first()
            #expect(updated?.state == .accepted)
        }
    }

    @Test("POST reject changes state to rejected")
    func rejectSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: "test.example",
                inboxURL: "https://test.example/inbox",
                actorID: "https://test.example/actor",
                state: .pending,
                followActivityID: "https://test.example/follow/1"
            )
            try await sub.save(on: app.db)

            try await app.testing().test(
                .POST,
                "api/admin/subscribers/test.example/reject",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("rejected"))
            }

            let updated = try await Subscriber.query(on: app.db)
                .filter(\.$domain == "test.example")
                .first()
            #expect(updated?.state == .rejected)
        }
    }

    @Test("DELETE removes subscriber")
    func removeSubscriber() async throws {
        try await withApp(configure: testConfigure) { app in
            let sub = Subscriber(
                domain: "test.example",
                inboxURL: "https://test.example/inbox",
                actorID: "https://test.example/actor",
                state: .accepted,
                followActivityID: "https://test.example/follow/1"
            )
            try await sub.save(on: app.db)

            try await app.testing().test(
                .DELETE,
                "api/admin/subscribers/test.example",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("removed"))
            }

            let count = try await Subscriber.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    @Test("Accept non-existent subscriber returns 404")
    func acceptNonExistent() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(
                .POST,
                "api/admin/subscribers/nonexistent.example/accept",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .notFound)
            }
        }
    }

    // MARK: - Blocked Domains

    @Test("GET blocked domains returns list")
    func listBlockedDomains() async throws {
        try await withApp(configure: testConfigure) { app in
            let blocked = BlockedDomain(domain: "bad.example", reason: "spam")
            try await blocked.save(on: app.db)

            try await app.testing().test(
                .GET,
                "api/admin/blocked-domains",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("bad.example"))
            }
        }
    }

    @Test("POST blocks domain and removes existing subscriber")
    func blockDomain() async throws {
        try await withApp(configure: testConfigure) { app in
            // Create a subscriber for the domain to be blocked.
            let sub = Subscriber(
                domain: "bad.example",
                inboxURL: "https://bad.example/inbox",
                actorID: "https://bad.example/actor",
                state: .accepted,
                followActivityID: "https://bad.example/follow/1"
            )
            try await sub.save(on: app.db)

            var blockHeaders = authHeaders
            blockHeaders.contentType = .json

            try await app.testing().test(
                .POST,
                "api/admin/blocked-domains",
                headers: blockHeaders,
                body: ByteBuffer(string: "{\"domain\":\"bad.example\",\"reason\":\"spam\"}")
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("blocked"))
            }

            let subCount = try await Subscriber.query(on: app.db).count()
            #expect(subCount == 0)

            let blockCount = try await BlockedDomain.query(on: app.db).count()
            #expect(blockCount == 1)
        }
    }

    @Test("POST block already-blocked domain returns 409")
    func blockAlreadyBlocked() async throws {
        try await withApp(configure: testConfigure) { app in
            let blocked = BlockedDomain(domain: "bad.example")
            try await blocked.save(on: app.db)

            var blockHeaders = authHeaders
            blockHeaders.contentType = .json

            try await app.testing().test(
                .POST,
                "api/admin/blocked-domains",
                headers: blockHeaders,
                body: ByteBuffer(string: "{\"domain\":\"bad.example\"}")
            ) { res async in
                #expect(res.status == .conflict)
            }
        }
    }

    @Test("DELETE unblocks domain")
    func unblockDomain() async throws {
        try await withApp(configure: testConfigure) { app in
            let blocked = BlockedDomain(domain: "bad.example")
            try await blocked.save(on: app.db)

            try await app.testing().test(
                .DELETE,
                "api/admin/blocked-domains/bad.example",
                headers: authHeaders
            ) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("unblocked"))
            }

            let count = try await BlockedDomain.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    // MARK: - Auth

    @Test("All admin endpoints without token return 401")
    func unauthorized() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "api/admin/subscribers") { res async in
                #expect(res.status == .unauthorized)
            }
            try await app.testing().test(.GET, "api/admin/blocked-domains") { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Admin endpoints with ADMIN_TOKEN unset return 403")
    func noAdminToken() async throws {
        setenv("ADMIN_TOKEN", "", 1)
        try await withApp(configure: { app in
            setenv("RELAY_DOMAIN", "localhost", 1)
            setenv("ADMIN_TOKEN", "", 1)
            try await APRelay.configure(app)
            app.actorFetcher = MockActorFetcher()
        }) { app in
            try await app.testing().test(.GET, "api/admin/subscribers") { res async in
                #expect(res.status == .forbidden)
            }
        }
    }
}

import Testing
import VaporTesting
@testable import APRelay

@Suite("Route Tests", .serialized)
struct RouteTests {
    @Test("GET / returns HTML")
    func indexPage() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.type == "text")
                #expect(res.body.string.contains("AP Relay"))
            }
        }
    }

    @Test("GET /actor returns ActivityPub actor")
    func actorEndpoint() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/actor") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "Content-Type") == "application/activity+json")
                let body = res.body.string
                #expect(body.contains("Application"))
                #expect(body.contains("publicKey"))
                #expect(body.contains("/inbox"))
            }
        }
    }

    @Test("GET /.well-known/webfinger with valid resource")
    func webfinger() async throws {
        try await withApp(configure: testConfigure) { app in
            let resource = "acct:relay@localhost"
            try await app.testing().test(
                .GET,
                ".well-known/webfinger?resource=\(resource)"
            ) { res async in
                #expect(res.status == .ok)
                #expect(
                    res.headers.first(name: "Content-Type") == "application/jrd+json"
                )
            }
        }
    }

    @Test("GET /.well-known/webfinger without resource returns 400")
    func webfingerMissingResource() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, ".well-known/webfinger") { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test("GET /.well-known/nodeinfo returns links")
    func nodeInfoWellKnown() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, ".well-known/nodeinfo") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("nodeinfo"))
            }
        }
    }

    @Test("GET /nodeinfo/2.1 returns node info")
    func nodeInfo() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "nodeinfo/2.1") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("aprelay"))
                #expect(res.body.string.contains("activitypub"))
            }
        }
    }

    @Test("GET /api/admin/subscribers without token returns 401")
    func adminUnauthorized() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "api/admin/subscribers") { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }
}

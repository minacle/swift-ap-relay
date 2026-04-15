import APRelayCore
import SwiftSoup
import Testing
import VaporTesting
@testable import APRelay

private func acceptLanguage(_ value: String) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.add(name: "Accept-Language", value: value)
    return headers
}

/// Maps locale → expected "how_to_subscribe" translation for parameterized tests.
private let howToSubscribeByLocale: [(locale: String, expected: String)] = [
    ("en", "How to Subscribe"),
    ("ja", "登録方法"),
    ("ko", "구독 방법"),
]

@Suite("HTML Localization Tests")
struct HTMLLocalizationTests {

    // MARK: - html lang Attribute

    @Test("Default request sets html lang to en")
    func defaultLangAttribute() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/") { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("html").attr("lang") == "en")
            }
        }
    }

    @Test("Accept-Language header sets html lang attribute", arguments: ["en", "ja", "ko"])
    func langAttributeMatchesAcceptLanguage(locale: String) async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage(locale)) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("html").attr("lang") == locale)
            }
        }
    }

    // MARK: - Localized UI Strings

    @Test("Locale renders correct UI strings", arguments: howToSubscribeByLocale)
    func localizedUIStrings(locale: String, expected: String) async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage(locale)) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try !doc.select("h2:contains(\(expected))").isEmpty())
            }
        }
    }

    // MARK: - Fallback

    @Test("Unsupported locale falls back to English")
    func unsupportedLocaleFallback() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage("xx")) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("html").attr("lang") == "en")
                #expect(try !doc.select("h2:contains(How to Subscribe)").isEmpty())
            }
        }
    }

    @Test("Quality-weighted Accept-Language selects highest priority locale")
    func qualityWeightedSelection() async throws {
        try await withApp(configure: testConfigure) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage("xx;q=0.5,ko;q=0.9,en;q=0.8")) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("html").attr("lang") == "ko")
                #expect(try !doc.select("h2:contains(구독 방법)").isEmpty())
            }
        }
    }

    // MARK: - Localized Relay Name / Description / Footer

    @Test("Localized relay name renders per locale")
    func localizedRelayName() async throws {
        try await withApp(configure: { app in
            try await testConfigure(app)
            app.relayConfig = RelayConfiguration(
                baseURL: "http://localhost",
                adminToken: "test-token",
                relayName: LocalizedString(["und": "My Relay", "ko": "내 릴레이"])
            )
        }) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage("ko")) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("title").text() == "내 릴레이")
                #expect(try doc.select("h1").first()?.text() == "내 릴레이")
            }

            try await app.testing().test(.GET, "/") { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("title").text() == "My Relay")
            }
        }
    }

    @Test("Localized description renders per locale")
    func localizedDescription() async throws {
        try await withApp(configure: { app in
            try await testConfigure(app)
            app.relayConfig = RelayConfiguration(
                baseURL: "http://localhost",
                adminToken: "test-token",
                relayDescription: LocalizedString(["und": "<p>A public relay</p>", "ko": "<p>공개 릴레이</p>"])
            )
        }) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage("ko")) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select(".description").first()?.text() == "공개 릴레이")
            }

            try await app.testing().test(.GET, "/") { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select(".description").first()?.text() == "A public relay")
            }
        }
    }

    @Test("Localized footer renders per locale")
    func localizedFooter() async throws {
        try await withApp(configure: { app in
            try await testConfigure(app)
            app.relayConfig = RelayConfiguration(
                baseURL: "http://localhost",
                adminToken: "test-token",
                relayFooter: LocalizedString(["und": "<span>Custom Footer</span>", "ja": "<span>カスタムフッター</span>"])
            )
        }) { app in
            try await app.testing().test(.GET, "/", headers: acceptLanguage("ja")) { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("footer .custom-footer").first()?.text() == "カスタムフッター")
            }

            try await app.testing().test(.GET, "/") { res async throws in
                let doc = try SwiftSoup.parse(res.body.string)
                #expect(try doc.select("footer .custom-footer").first()?.text() == "Custom Footer")
            }
        }
    }
}

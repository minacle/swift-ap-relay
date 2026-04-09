import Fluent
import Vapor

struct IndexController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: index)
    }

    @Sendable
    private func index(req: Request) async throws -> Response {
        let config = req.relayConfig

        let subscribers = try await Subscriber.query(on: req.db)
            .filter(\.$state == .accepted)
            .all()

        let instanceListHTML: String
        if subscribers.isEmpty {
            instanceListHTML = "<p>No connected instances yet.</p>"
        } else {
            let items = subscribers.map { sub in
                "<li>\(escapeHTML(sub.domain))</li>"
            }.joined(separator: "\n            ")
            instanceListHTML = """
                <ul>
                    \(items)
                </ul>
                """
        }

        let descriptionHTML =
            config.relayDescription.isEmpty
            ? ""
            : "<div class=\"description\">\(config.relayDescription)</div>"

        let footerHTML =
            config.relayFooter.isEmpty
            ? ""
            : "<footer>\(config.relayFooter)</footer>"

        let html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>AP Relay - \(escapeHTML(config.domain))</title>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                        max-width: 800px;
                        margin: 0 auto;
                        padding: 2rem 1rem;
                        color: #333;
                        line-height: 1.6;
                    }
                    h1 { color: #1a1a2e; }
                    .info { background: #f0f4f8; padding: 1rem; border-radius: 8px; margin: 1rem 0; }
                    .info code { background: #e2e8f0; padding: 0.2rem 0.4rem; border-radius: 4px; }
                    .description { margin: 1rem 0; }
                    .instances { margin: 2rem 0; }
                    .instances ul { columns: 2; list-style: none; padding: 0; }
                    .instances li { padding: 0.25rem 0; }
                    footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #e2e8f0; color: #666; }
                    .badge { display: inline-block; background: #6c5ce7; color: white; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.85rem; }
                </style>
            </head>
            <body>
                <h1>AP Relay</h1>
                <p><span class="badge">\(escapeHTML(config.domain))</span></p>
                \(descriptionHTML)
                <div class="info">
                    <h2>How to Subscribe</h2>
                    <p><strong>Mastodon</strong> / <strong>Misskey</strong>: add this relay URL in your admin settings:</p>
                    <p><code>\(escapeHTML(config.inboxURL))</code></p>
                    <p><strong>Pleroma</strong> / <strong>Akkoma</strong>: follow this actor in your relay settings:</p>
                    <p><code>\(escapeHTML(config.actorURL))</code></p>
                </div>
                <div class="instances">
                    <h2>Connected Instances (\(subscribers.count))</h2>
                    \(instanceListHTML)
                </div>
                \(footerHTML)
                <p style="color: #999; font-size: 0.8rem;">Powered by <a href="https://github.com/sinoru/swift-ap-relay">AP Relay</a></p>
            </body>
            </html>
            """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .init(string: html)
        )
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

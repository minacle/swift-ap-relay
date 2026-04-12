import Vapor

struct WebFingerController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped(".well-known").get("webfinger", use: webfinger)
    }

    @Sendable
    private func webfinger(req: Request) async throws -> WebFingerResponse {
        let config = req.relayConfig

        guard let resource = req.query[String.self, at: "resource"] else {
            throw Abort(.badRequest, reason: "Missing 'resource' query parameter")
        }

        let expectedResource = "acct:relay@\(config.domain)"
        guard resource == expectedResource else {
            throw Abort(.notFound, reason: "Unknown resource")
        }

        return WebFingerResponse(
            subject: expectedResource,
            links: [
                WebFingerLink(
                    rel: "self",
                    type: "application/activity+json",
                    href: config.actorURL
                ),
            ]
        )
    }
}

private struct WebFingerResponse: Content {
    static var defaultContentType: HTTPMediaType {
        .init(type: "application", subType: "jrd+json")
    }

    let subject: String
    let links: [WebFingerLink]

    func encodeResponse(for request: Request) async throws -> Response {
        let response = Response()
        try response.content.encode(self)
        // Vapor's JSONEncoder always overrides Content-Type to application/json;
        // restore the intended media type.
        response.headers.contentType = Self.defaultContentType
        return response
    }
}

private struct WebFingerLink: Codable, Sendable {
    let rel: String
    let type: String
    let href: String
}

import Vapor

struct WebFingerController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped(".well-known").get("webfinger", use: webfinger)
    }

    @Sendable
    private func webfinger(req: Request) async throws -> Response {
        let config = req.relayConfig

        guard let resource = req.query[String.self, at: "resource"] else {
            throw Abort(.badRequest, reason: "Missing 'resource' query parameter")
        }

        let expectedResource = "acct:relay@\(config.domain)"
        guard resource == expectedResource else {
            throw Abort(.notFound, reason: "Unknown resource")
        }

        let response = WebFingerResponse(
            subject: expectedResource,
            links: [
                WebFingerLink(
                    rel: "self",
                    type: "application/activity+json",
                    href: config.actorURL
                ),
            ]
        )

        let data = try JSONEncoder().encode(response)
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/jrd+json"],
            body: .init(data: data)
        )
    }
}

private struct WebFingerResponse: Codable {
    let subject: String
    let links: [WebFingerLink]
}

private struct WebFingerLink: Codable {
    let rel: String
    let type: String
    let href: String
}

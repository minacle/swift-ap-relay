import Vapor

/// Wrapper for ActivityPub JSON responses with `application/activity+json` content type.
struct ActivityJSON<T: Codable & Sendable>: AsyncResponseEncodable, Sendable {
    private static var mediaType: HTTPMediaType {
        .init(type: "application", subType: "activity+json")
    }

    let value: T

    init(_ value: T) {
        self.value = value
    }

    func encodeResponse(for request: Request) async throws -> Response {
        let response = Response()
        try response.content.encode(value, as: Self.mediaType)
        // Vapor's JSONEncoder always overrides Content-Type to application/json;
        // restore the intended media type.
        response.headers.contentType = Self.mediaType
        return response
    }
}

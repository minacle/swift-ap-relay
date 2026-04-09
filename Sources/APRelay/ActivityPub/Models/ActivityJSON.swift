import Vapor

/// Wrapper for ActivityPub JSON responses with `application/activity+json` content type.
struct ActivityJSON<T: Codable & Sendable>: AsyncResponseEncodable, Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }

    func encodeResponse(for request: Request) async throws -> Response {
        let data = try JSONEncoder().encode(value)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/activity+json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

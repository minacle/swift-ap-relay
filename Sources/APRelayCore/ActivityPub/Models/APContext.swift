import Foundation

/// JSON-LD `@context` that can be either a single string or an array of strings.
public enum APContext: Codable, Sendable {
    case single(String)
    case array([String])

    public static let activityStreams = "https://www.w3.org/ns/activitystreams"
    public static let securityV1 = "https://w3id.org/security/v1"

    /// Default context for relay actor and outgoing activities.
    public static let `default` = APContext.array([activityStreams, securityV1])

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
        } else if let values = try? container.decode([String].self) {
            self = .array(values)
        } else if let mixed = try? container.decode([APContextElement].self) {
            // Handle mixed arrays like ["https://...", {"@language": "und"}]
            // (Pleroma/Akkoma send this format).
            let strings = mixed.compactMap(\.stringValue)
            self = strings.count == 1
                ? .single(strings[0])
                : .array(strings)
        } else {
            self = .single(APContext.activityStreams)
        }
    }
}

/// Element within a JSON-LD @context array that can be either a string or an object.
private enum APContextElement: Decodable {
    case string(String)
    case object

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            // Consume the value (object, number, etc.) without storing it.
            _ = try container.decode(EmptyDecodable.self)
            self = .object
        }
    }
}

/// Placeholder that accepts any single JSON value.
private struct EmptyDecodable: Decodable {
    init(from decoder: any Decoder) throws {
        // Accept any value by decoding as AnyCodableValue.
        let container = try decoder.singleValueContainer()
        if (try? container.decode([String: String].self)) != nil { return }
        if (try? container.decode([String: Bool].self)) != nil { return }
        if (try? container.decode([String: Int].self)) != nil { return }
        // Accept any remaining JSON object/array/value.
        _ = try? container.decode([String: String?].self)
    }
}

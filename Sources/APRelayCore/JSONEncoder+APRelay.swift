import Foundation

extension JSONEncoder {
    /// Shared encoder for all AP Relay JSON output with deterministic key ordering.
    package static let apRelay: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

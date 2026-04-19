import Foundation

extension Date.ISO8601FormatStyle {
    /// Shared ISO 8601 format style for ActivityPub activity timestamps.
    /// Output matches the default `ISO8601DateFormatter`: `yyyy-MM-ddTHH:mm:ssZ`.
    package static let apRelay = Date.ISO8601FormatStyle()
}

import Collections
import Foundation

/// Thread-safe LRU cache for detecting duplicate activity IDs.
public actor ActivityDeduplicator {
    public static let shared = ActivityDeduplicator()

    private var cache: OrderedDictionary<String, Date> = [:]
    private let maxSize: Int
    private let ttl: TimeInterval

    public init(maxSize: Int = 10_000, ttl: TimeInterval = 3600) {
        self.maxSize = maxSize
        self.ttl = ttl
    }

    /// Returns `true` if this activity ID was already seen recently.
    public func isDuplicate(_ activityID: String) -> Bool {
        evictExpired()

        if cache[activityID] != nil {
            return true
        }

        cache[activityID] = Date()

        while cache.count > maxSize {
            cache.removeFirst()
        }

        return false
    }

    private func evictExpired() {
        let cutoff = Date().addingTimeInterval(-ttl)
        while let first = cache.elements.first, first.value < cutoff {
            cache.removeFirst()
        }
    }
}

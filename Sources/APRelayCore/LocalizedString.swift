import Foundation

/// A locale-aware string wrapper backed by a `[String: String]` dictionary.
///
/// Keys are BCP 47 locale identifiers (e.g. `"ko"`, `"zh-TW"`).
/// The special key `"und"` (undetermined) holds the default/unlocalized value.
package struct LocalizedString: Sendable, Equatable {
    package let values: [String: String]

    package init(_ values: [String: String]) {
        self.values = values
    }

    /// Resolves the best value for the given locale preference list.
    ///
    /// Resolution order for each preference:
    /// 1. Exact match (e.g. `"zh-TW"` matches key `"zh-TW"`)
    /// 2. Language-only fallback (e.g. `"zh-TW"` tries key `"zh"`)
    /// 3. Reverse match (e.g. `"zh"` matches key `"zh-TW"`)
    ///
    /// After all preferences are exhausted, falls back to `"und"`, then `nil`.
    package func value(for preferences: [String]) -> String? {
        for pref in preferences {
            // Exact match
            if let v = values[pref] {
                return v
            }
            // Language-only fallback
            let language = Self.languagePart(of: pref)
            if language != pref, let v = values[language] {
                return v
            }
            // Reverse match: preference is language-only, find a key with that language
            if let match = values.keys.sorted().first(where: { Self.languagePart(of: $0) == pref }) {
                return values[match]
            }
        }
        return values["und"]
    }

    /// Returns the unlocalized (`"und"`) value, or `nil` if not set.
    package func unlocalizedValue() -> String? {
        values["und"]
    }

    // MARK: - Private

    private static func languagePart(of locale: String) -> String {
        if let idx = locale.firstIndex(of: "-") {
            return String(locale[..<idx])
        }
        return locale
    }
}

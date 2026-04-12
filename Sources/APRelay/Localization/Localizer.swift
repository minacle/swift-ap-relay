import Foundation
import Vapor

/// Lightweight i18n system with Accept-Language support and
/// language+region fallback (e.g. `zh-TW` → `zh` → `en`).
struct Localizer: Sendable {
    /// [locale: [key: value]] — e.g. ["en": ["hello": "Hello"], "ko": ["hello": "안녕"]]
    private let translations: [String: [String: String]]

    /// Ordered list of available locale identifiers (e.g. ["en", "ko", "ja", "zh-TW"]).
    let availableLocales: [String]

    let defaultLocale: String

    /// Loads all JSON translation files from the given directory.
    /// Files must be named `{locale}.json` (e.g. `en.json`, `zh-TW.json`).
    init(directory: String, defaultLocale: String = "en") throws {
        self.defaultLocale = defaultLocale

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory) else {
            self.translations = [:]
            self.availableLocales = []
            return
        }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var loaded: [String: [String: String]] = [:]
        for file in files {
            let locale = file.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: file)
            let dict = try JSONDecoder().decode([String: String].self, from: data)
            loaded[locale] = dict
        }

        self.translations = loaded
        self.availableLocales = loaded.keys.sorted()
    }

    /// Selects the best available locale from an Accept-Language header value.
    ///
    /// Parses quality factors and applies the fallback chain:
    /// 1. Exact match (`zh-TW`)
    /// 2. Language-only match (`zh`)
    /// 3. Default locale
    func bestLocale(acceptLanguage: String?) -> String {
        guard let header = acceptLanguage, !header.isEmpty else {
            return defaultLocale
        }

        let preferences = Self.parseAcceptLanguage(header)

        for pref in preferences {
            // Exact match (e.g. "zh-TW" matches "zh-TW")
            if translations[pref.locale] != nil {
                return pref.locale
            }
            // Try language-only (e.g. "zh-TW" → try "zh")
            let language = Self.languagePart(of: pref.locale)
            if language != pref.locale, translations[language] != nil {
                return language
            }
            // Try matching available locales that share the same language
            // (e.g. request "zh" → match "zh-TW" if only "zh-TW" is available)
            if let match = availableLocales.first(where: { Self.languagePart(of: $0) == pref.locale }) {
                return match
            }
        }

        return defaultLocale
    }

    /// Returns the localized string for a key, using the fallback chain:
    /// `locale` → language-only → default locale → key itself.
    func localize(_ key: String, locale: String) -> String {
        // Exact locale
        if let value = translations[locale]?[key] {
            return value
        }
        // Language-only fallback
        let language = Self.languagePart(of: locale)
        if language != locale, let value = translations[language]?[key] {
            return value
        }
        // Default locale fallback
        if locale != defaultLocale, let value = translations[defaultLocale]?[key] {
            return value
        }
        // Key itself as last resort
        return key
    }

    /// Returns locale identifiers sorted by quality (descending) from an Accept-Language header.
    static func sortedLocalePreferences(acceptLanguage: String?) -> [String] {
        guard let header = acceptLanguage, !header.isEmpty else { return [] }
        return parseAcceptLanguage(header).map(\.locale)
    }
}

// MARK: - Accept-Language Parsing

extension Localizer {
    struct LanguagePreference: Comparable {
        let locale: String
        let quality: Double

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.quality > rhs.quality  // Higher quality first
        }
    }

    /// Parses `Accept-Language` header into sorted preferences.
    /// Example: `"ko,en-US;q=0.9,en;q=0.8"` →
    ///   `[("ko", 1.0), ("en-US", 0.9), ("en", 0.8)]`
    static func parseAcceptLanguage(_ header: String) -> [LanguagePreference] {
        header
            .split(separator: ",")
            .compactMap { entry -> LanguagePreference? in
                let parts = entry.split(separator: ";").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard let locale = parts.first, !locale.isEmpty, locale != "*" else {
                    return nil
                }
                let quality: Double
                if parts.count > 1,
                   let qPart = parts.dropFirst().first(where: { $0.hasPrefix("q=") })
                {
                    quality = Double(qPart.dropFirst(2)) ?? 1.0
                } else {
                    quality = 1.0
                }
                // Normalize: "en_US" → "en-US", lowercase language, uppercase region
                let normalized = normalizeLocale(String(locale))
                return LanguagePreference(locale: normalized, quality: quality)
            }
            .sorted()
    }

    /// Extracts language part: `"zh-TW"` → `"zh"`, `"en"` → `"en"`.
    private static func languagePart(of locale: String) -> String {
        if let idx = locale.firstIndex(of: "-") {
            return String(locale[..<idx])
        }
        return locale
    }

    /// Normalizes locale identifier: lowercase language, uppercase region.
    /// `"EN_us"` → `"en-US"`, `"zh-tw"` → `"zh-TW"`
    private static func normalizeLocale(_ locale: String) -> String {
        let parts = locale.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard let language = parts.first else { return locale }
        if parts.count > 1 {
            let subtags = parts.dropFirst().map { subtag -> String in
                if subtag.count == 4 && subtag.allSatisfy(\.isLetter) {
                    // Script subtag: Title Case (e.g., Hant, Latn)
                    return subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
                } else {
                    // Region subtag (2 letters / 3 digits) or variant
                    return subtag.uppercased()
                }
            }.joined(separator: "-")
            return "\(language.lowercased())-\(subtags)"
        }
        return language.lowercased()
    }
}

// MARK: - Vapor Storage Integration

private struct LocalizerKey: StorageKey {
    typealias Value = Localizer
}

extension Application {
    var localizer: Localizer {
        get {
            guard let localizer = storage[LocalizerKey.self] else {
                fatalError("Localizer not configured. Call configure() first.")
            }
            return localizer
        }
        set {
            storage[LocalizerKey.self] = newValue
        }
    }
}

extension Request {
    var localizer: Localizer {
        application.localizer
    }

    /// Determines the best locale for this request based on Accept-Language.
    var preferredLocale: String {
        localizer.bestLocale(acceptLanguage: headers[.acceptLanguage].first)
    }

    /// Returns locale identifiers sorted by quality from the Accept-Language header.
    var preferredLocales: [String] {
        Localizer.sortedLocalePreferences(acceptLanguage: headers[.acceptLanguage].first)
    }
}

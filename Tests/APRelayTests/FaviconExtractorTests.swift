import Foundation
import Testing
@testable import APRelay

@Suite("Favicon Extractor Tests")
struct FaviconExtractorTests {

    private let baseURL = URL(string: "https://example.com/")!

    // MARK: - Basic Extraction

    @Test("Extracts standard rel=icon href")
    func standardIcon() {
        let html = """
        <html><head><link rel="icon" href="/favicon.png"></head><body></body></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/favicon.png")
    }

    @Test("Extracts shortcut icon href")
    func shortcutIcon() {
        let html = """
        <html><head><link rel="shortcut icon" href="/favicon.ico"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/favicon.ico")
    }

    @Test("Extracts apple-touch-icon href")
    func appleTouchIcon() {
        let html = """
        <html><head><link rel="apple-touch-icon" href="/apple-icon.png"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/apple-icon.png")
    }

    // MARK: - Attribute Order

    @Test("Handles href before rel (reversed attribute order)")
    func hrefBeforeRel() {
        let html = """
        <html><head><link href="/icon.png" rel="icon"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }

    // MARK: - URL Resolution

    @Test("Resolves relative URL against base URL")
    func relativeURL() {
        let html = """
        <html><head><link rel="icon" href="images/favicon.png"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/images/favicon.png")
    }

    @Test("Returns absolute URL as-is")
    func absoluteURL() {
        let html = """
        <html><head><link rel="icon" href="https://cdn.example.com/icon.png"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://cdn.example.com/icon.png")
    }

    // MARK: - No Match Cases

    @Test("Returns nil for no matching link tags")
    func noMatchingTags() {
        let html = """
        <html><head><link rel="stylesheet" href="/style.css"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Returns nil for empty HTML")
    func emptyHTML() {
        let result = extractFaviconURL(fromHTML: "", baseURL: baseURL)
        #expect(result == nil)
    }

    // MARK: - Sizes-Based Priority

    @Test("Prefers 32x32 over 16x16 for Retina")
    func prefers32x32() {
        let html = """
        <html><head>
        <link rel="icon" sizes="16x16" href="/icon-16.png">
        <link rel="icon" sizes="32x32" href="/icon-32.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon-32.png")
    }

    @Test("Prefers 32x32 over unspecified size")
    func prefers32x32OverNoSize() {
        let html = """
        <html><head>
        <link rel="icon" href="/icon-default.png">
        <link rel="icon" sizes="32x32" href="/icon-32.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon-32.png")
    }

    @Test("Prefers 16x16 over unspecified size")
    func prefers16x16OverNoSize() {
        let html = """
        <html><head>
        <link rel="icon" href="/icon-default.png">
        <link rel="icon" sizes="16x16" href="/icon-16.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon-16.png")
    }

    // MARK: - Rel-Type Priority

    @Test("Prefers icon over shortcut icon")
    func prefersIconOverShortcut() {
        let html = """
        <html><head>
        <link rel="shortcut icon" href="/shortcut.ico">
        <link rel="icon" href="/icon.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }

    @Test("Prefers icon over apple-touch-icon")
    func prefersIconOverAppleTouch() {
        let html = """
        <html><head>
        <link rel="apple-touch-icon" href="/apple.png">
        <link rel="icon" href="/icon.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }

    // MARK: - Security

    @Test("Rejects javascript: scheme")
    func rejectsJavascriptScheme() {
        let html = """
        <html><head><link rel="icon" href="javascript:alert(1)"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == nil)
    }

    @Test("Rejects data: scheme")
    func rejectsDataScheme() {
        let html = """
        <html><head><link rel="icon" href="data:image/png;base64,abc"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == nil)
    }

    // MARK: - Case Insensitivity

    @Test("Handles case-insensitive rel attribute")
    func caseInsensitiveRel() {
        let html = """
        <html><head><link REL="ICON" HREF="/icon.png"></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }

    // MARK: - Quoting Variants

    @Test("Handles single-quoted attributes")
    func singleQuotedAttributes() {
        let html = """
        <html><head><link rel='icon' href='/icon.png'></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }

    // MARK: - Head Section Isolation

    @Test("Ignores link tags in body")
    func ignoresBodyTags() {
        let html = """
        <html><head><title>Test</title></head><body><link rel="icon" href="/body-icon.png"></body></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == nil)
    }

    // MARK: - Multiple Icons Best Selection

    @Test("Selects best from multiple icon tags with various sizes")
    func bestFromMultiple() {
        let html = """
        <html><head>
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="icon" type="image/png" sizes="192x192" href="/icon-192.png">
        <link rel="icon" type="image/png" sizes="32x32" href="/icon-32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/icon-16.png">
        </head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon-32.png")
    }

    // MARK: - Self-Closing Tags

    @Test("Handles self-closing link tags")
    func selfClosingTag() {
        let html = """
        <html><head><link rel="icon" href="/icon.png" /></head></html>
        """
        let result = extractFaviconURL(fromHTML: html, baseURL: baseURL)
        #expect(result == "https://example.com/icon.png")
    }
}

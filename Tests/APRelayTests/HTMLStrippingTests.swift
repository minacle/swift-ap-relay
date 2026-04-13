import Testing
@testable import APRelay

@Suite("HTML Stripping Tests")
struct HTMLStrippingTests {
    @Test("strips simple HTML tags")
    func simpleStrip() {
        let result = stripHTMLTags(from: "<p>Hello <b>world</b></p>")
        #expect(result == "Hello world")
    }

    @Test("decodes HTML entities")
    func entityDecoding() {
        let result = stripHTMLTags(from: "Tom &amp; Jerry &lt;3")
        #expect(result == "Tom & Jerry <3")
    }

    @Test("collapses whitespace")
    func whitespaceCollapse() {
        let result = stripHTMLTags(from: "<p>Hello</p>\n\n<p>World</p>")
        #expect(result == "Hello World")
    }

    @Test("returns empty string for empty input")
    func emptyInput() {
        let result = stripHTMLTags(from: "")
        #expect(result == "")
    }

    @Test("passes through plain text unchanged")
    func plainText() {
        let result = stripHTMLTags(from: "Just plain text")
        #expect(result == "Just plain text")
    }
}

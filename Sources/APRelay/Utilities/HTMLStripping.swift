import Foundation

/// Strips HTML tags from a string, decodes common entities, and normalizes whitespace.
///
/// Designed for relay operator-provided descriptions (trusted, simple HTML).
func stripHTMLTags(from html: String) -> String {
    guard !html.isEmpty else { return "" }

    var result = html.replacingOccurrences(
        of: "<[^>]+>",
        with: "",
        options: .regularExpression
    )

    result = result
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")

    result = result.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    return result
}

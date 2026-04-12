import Foundation

/// Extracts the best favicon URL from an HTML document's `<head>` section.
///
/// Scans for `<link>` elements with `rel="icon"`, `rel="shortcut icon"`,
/// or `rel="apple-touch-icon"`, preferring 32x32 for Retina display clarity.
///
/// - Parameters:
///   - html: The HTML string to scan (only the `<head>` section is examined).
///   - baseURL: The base URL for resolving relative `href` values.
/// - Returns: The absolute URL string of the best favicon, or `nil` if none found.
func extractFaviconURL(fromHTML html: String, baseURL: URL) -> String? {
    // Only scan the <head> section to avoid false matches in body content.
    let headHTML: String
    if let headEndRange = html.range(of: "</head>", options: .caseInsensitive) {
        headHTML = String(html[..<headEndRange.lowerBound])
    } else {
        headHTML = html
    }

    // Match all <link ...> tags (self-closing or not).
    let linkPattern = /<link\b[^>]*>/

    var candidates: [FaviconCandidate] = []

    for match in headHTML.matches(of: linkPattern) {
        let tag = String(match.output)

        guard let rel = extractAttribute("rel", from: tag)?.lowercased() else { continue }

        let relType: FaviconRelType
        switch rel {
        case "icon":
            relType = .icon
        case "shortcut icon":
            relType = .shortcutIcon
        case "apple-touch-icon", "apple-touch-icon-precomposed":
            relType = .appleTouchIcon
        default:
            continue
        }

        guard let href = extractAttribute("href", from: tag) else { continue }

        // Resolve relative URL
        guard let resolvedURL = URL(string: href, relativeTo: baseURL) else { continue }
        let absoluteString = resolvedURL.absoluteString

        // Only allow http/https schemes
        let scheme = resolvedURL.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { continue }

        // Parse sizes attribute (e.g. "32x32", "16x16")
        let size = extractAttribute("sizes", from: tag).flatMap { parseSizeValue($0) }

        candidates.append(FaviconCandidate(url: absoluteString, rel: relType, size: size))
    }

    guard !candidates.isEmpty else { return nil }

    // Sort by priority: lower score = better
    candidates.sort { $0.score < $1.score }

    return candidates.first?.url
}

// MARK: - Private Types

private enum FaviconRelType: Int {
    case icon = 0
    case shortcutIcon = 1
    case appleTouchIcon = 2
}

private struct FaviconCandidate {
    let url: String
    let rel: FaviconRelType
    let size: Int?  // Width in pixels (assumes square)

    /// Lower score = higher priority.
    /// Prefer 32x32 (Retina), then 16x16, then no size, then others by ascending size.
    var score: Int {
        let relScore = rel.rawValue * 1000

        guard let size else {
            // No size specified: middle priority within each rel type
            return relScore + 500
        }

        switch size {
        case 32:
            return relScore + 0   // Best: 32x32 for Retina
        case 16:
            return relScore + 1   // Second: standard 16x16
        default:
            // Other sizes: prefer smaller ones, but after 32 and 16
            return relScore + 100 + size
        }
    }
}

// MARK: - Attribute Parsing

/// Extracts an HTML attribute value from a tag string.
///
/// Handles both single and double quoted values, and attributes in any order.
private func extractAttribute(_ name: String, from tag: String) -> String? {
    // Pattern: name = "value" or name = 'value'
    // Case-insensitive match for the attribute name
    let pattern = try! Regex("\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
        .ignoresCase()

    guard let match = tag.firstMatch(of: pattern) else { return nil }

    // Return whichever capture group matched (double quotes or single quotes)
    if let value = match.output[1].substring {
        return String(value)
    }
    if let value = match.output[2].substring {
        return String(value)
    }
    return nil
}

/// Parses a `sizes` attribute value like "32x32" into a single dimension.
private func parseSizeValue(_ sizes: String) -> Int? {
    let parts = sizes.lowercased().split(separator: "x")
    guard parts.count == 2,
          let width = Int(parts[0]),
          width > 0
    else { return nil }
    return width
}

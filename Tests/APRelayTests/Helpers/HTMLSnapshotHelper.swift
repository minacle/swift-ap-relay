import Foundation
import Vapor
import VaporTesting
@testable import APRelay

/// Writes a rendered HTML string to disk as a self-contained snapshot file.
///
/// The snapshot inlines the project's `style.css` so the file can be opened
/// directly in a browser without running the server.
///
/// When `locale` is provided, the file is written to a locale subdirectory
/// (e.g. `{dir}/en/{name}.html`).
///
/// Snapshots are only written when the `HTML_SNAPSHOT_DIR` environment
/// variable is set. Example usage:
///
///     HTML_SNAPSHOT_DIR=html-snapshots swift test --filter HTMLSnapshotTests
///
func saveHTMLSnapshot(_ html: String, name: String, locale: String? = nil, app: Application) throws {
    guard let snapshotDir = ProcessInfo.processInfo.environment["HTML_SNAPSHOT_DIR"] else {
        return
    }

    // Validate that snapshotDir is a non-empty relative path without traversal.
    guard !snapshotDir.isEmpty,
          !snapshotDir.hasPrefix("/"),
          !snapshotDir.hasPrefix("~"),
          !snapshotDir.split(separator: "/").contains("..") else {
        throw Abort(.internalServerError, reason: "HTML_SNAPSHOT_DIR must be a non-empty relative path without '..' components")
    }

    // Sanitize name to prevent path traversal.
    guard !name.isEmpty,
          !name.contains("/"),
          !name.contains("\\"),
          !name.contains("..") else {
        throw Abort(.internalServerError, reason: "Snapshot name contains invalid characters")
    }

    // Read CSS from the Public directory and inline it.
    let cssPath = app.directory.publicDirectory + "css/style.css"
    let css = try String(contentsOfFile: cssPath, encoding: .utf8)
    let linkPattern = #"<link\b[^>]*\brel="stylesheet"[^>]*>"#
    guard html.range(of: linkPattern, options: .regularExpression) != nil else {
        throw Abort(.internalServerError, reason: "Expected <link rel=\"stylesheet\"> tag not found in HTML output")
    }
    let inlinedHTML = html.replacingOccurrences(
        of: linkPattern,
        with: "<style>\n\(css)\n</style>",
        options: .regularExpression
    )

    let rootDir = URL(fileURLWithPath: snapshotDir)
    try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

    // Ensure a .gitignore exists so snapshot output is never committed.
    let gitignoreURL = rootDir.appendingPathComponent(".gitignore")
    if !FileManager.default.fileExists(atPath: gitignoreURL.path) {
        try "*\n.*\n".write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }

    let outputDir: URL
    if let locale {
        // Sanitize locale to allow only safe characters.
        let sanitizedLocale = String(locale.unicodeScalars.filter {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0)
        })
        guard !sanitizedLocale.isEmpty else {
            throw Abort(.internalServerError, reason: "Locale value is empty after sanitization")
        }
        outputDir = rootDir.appendingPathComponent(sanitizedLocale)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } else {
        outputDir = rootDir
    }

    let fileURL = outputDir.appendingPathComponent("\(name).html")
    try inlinedHTML.write(to: fileURL, atomically: true, encoding: .utf8)
}

/// Renders the page for every available locale and saves each as a snapshot.
///
/// Sends `GET /` with the appropriate `Accept-Language` header for each
/// locale known to the app's localizer.
func saveHTMLSnapshotsForAllLocales(name: String, app: Application) async throws {
    for locale in app.localizer.availableLocales {
        let headers = HTTPHeaders([("Accept-Language", locale)])
        try await app.testing().test(.GET, "/", headers: headers) { res async throws in
            guard res.status == .ok else {
                throw Abort(.internalServerError, reason: "Expected HTTP 200 for locale '\(locale)', got \(res.status)")
            }
            try saveHTMLSnapshot(res.body.string, name: name, locale: locale, app: app)
        }
    }
}

import Foundation
import Vapor
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

    // Read CSS from the Public directory and inline it.
    let cssPath = app.directory.publicDirectory + "css/style.css"
    let css = try String(contentsOfFile: cssPath, encoding: .utf8)
    let inlinedHTML = html.replacingOccurrences(
        of: #"<link rel="stylesheet" href="/css/style.css">"#,
        with: "<style>\n\(css)\n</style>"
    )

    let rootDir = URL(fileURLWithPath: snapshotDir)
    try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

    // Ensure a .gitignore exists so snapshot output is never committed.
    let gitignoreURL = rootDir.appendingPathComponent(".gitignore")
    if !FileManager.default.fileExists(atPath: gitignoreURL.path) {
        try "*\n".write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }

    let outputDir: URL
    if let locale {
        outputDir = rootDir.appendingPathComponent(locale)
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
            try saveHTMLSnapshot(res.body.string, name: name, locale: locale, app: app)
        }
    }
}

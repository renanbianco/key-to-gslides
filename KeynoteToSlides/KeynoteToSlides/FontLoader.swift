// FontLoader.swift
// Downloads Google Fonts as TTF, caches them locally, and registers with CoreText
// so Font.custom() can render them in the dropdown.

import CoreText
import Foundation
import AppKit

@MainActor
final class FontLoader: ObservableObject {

    static let shared = FontLoader()

    /// Family names that are registered and ready to render.
    @Published private(set) var loadedFamilies: Set<String> = []

    private var inFlight: Set<String> = []

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("KeynoteToSlides/FontCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private init() {
        preloadCached()
        // Mark system fonts as already loaded
        let systemFamilies = Set(NSFontManager.shared.availableFontFamilies)
        loadedFamilies.formUnion(systemFamilies)
    }

    // MARK: - Public API

    /// Call this for each font name that should appear styled in the dropdown.
    func load(_ family: String) {
        guard !loadedFamilies.contains(family), !inFlight.contains(family) else { return }
        inFlight.insert(family)
        Task { await fetchAndRegister(family) }
    }

    // MARK: - Private

    /// Register any TTF files already cached from previous runs.
    private func preloadCached() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            let family = file.deletingPathExtension().lastPathComponent
            if registerFont(at: file) { loadedFamilies.insert(family) }
        }
    }

    private func fetchAndRegister(_ family: String) async {
        defer { inFlight.remove(family) }

        let cacheFile = cacheDir.appendingPathComponent("\(family).ttf")

        // Use disk cache if available
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            if registerFont(at: cacheFile) { loadedFamilies.insert(family) }
            return
        }

        // Fetch CSS from Google Fonts v1 API.
        // An old User-Agent makes Google return TTF instead of WOFF2.
        let encoded = family.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? family
        guard let cssURL = URL(string: "https://fonts.googleapis.com/css?family=\(encoded)") else { return }

        var req = URLRequest(url: cssURL, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)",
                     forHTTPHeaderField: "User-Agent")

        guard let (cssData, _) = try? await URLSession.shared.data(for: req),
              let css = String(data: cssData, encoding: .utf8) else { return }

        // Extract the first TTF URL from the CSS
        let pattern = #"url\((https://fonts\.gstatic\.com/[^)]+\.ttf)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)),
              let urlRange = Range(match.range(at: 1), in: css),
              let fontURL = URL(string: String(css[urlRange])) else { return }

        guard let (fontData, _) = try? await URLSession.shared.data(from: fontURL) else { return }

        // Cache to disk then register
        try? fontData.write(to: cacheFile)
        if registerFont(at: cacheFile) { loadedFamilies.insert(family) }
    }

    @discardableResult
    private func registerFont(at url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return ok
    }
}

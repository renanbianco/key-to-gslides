// KeynoteExporter.swift
import Foundation
import AppKit   // NSWorkspace, NSRunningApplication, NSAppleScript

enum ExportError: LocalizedError {
    case fileNotFound(String)
    case keynoteNotFound
    case exportFailed(String)
    case timeout
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "Keynote file not found: \(p)\n\nIf stored in iCloud, make sure it's fully downloaded first."
        case .keynoteNotFound: return "Keynote app not found. Please install Keynote from the App Store."
        case .exportFailed(let msg): return "AppleScript export failed:\n\(msg)"
        case .timeout: return "Keynote export timed out (>180 s). The file may be very large or Keynote is unresponsive."
        case .emptyOutput: return "Export produced no output file. Check that Keynote can open this file."
        }
    }
}

struct KeynoteExporter {

    static func export(from fileURL: URL) async throws -> String {
        let resolved = try resolveURL(fileURL)

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw ExportError.fileNotFound(resolved.path)
        }

        // ── 1. Find and launch Keynote via NSWorkspace ─────────────────────────
        guard let keynoteURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Keynote") else {
            throw ExportError.keynoteNotFound
        }

        let isRunning = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.Keynote" }
        if !isRunning {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            cfg.hides = true
            try? await NSWorkspace.shared.openApplication(at: keynoteURL, configuration: cfg)
        }

        // Wait up to 15 s for Keynote to appear in the process list
        for _ in 0..<30 {
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Keynote" }) { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Keynote" }) else {
            throw ExportError.exportFailed("Keynote did not start within 15 seconds.")
        }
        // Give Keynote's scripting bridge a moment to initialise
        try await Task.sleep(for: .seconds(2))

        // ── 2. Prepare output path ─────────────────────────────────────────────
        let pptxURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pptx")

        let scriptSource = buildAppleScript(keynotePath: resolved.path, pptxPath: pptxURL.path)

        // ── 3. Execute via NSAppleScript in our own process ────────────────────
        // For a non-sandboxed app with Hardened Runtime, NSAppleScript in-process
        // is the correct approach. The TCC Automation consent prompt appears to the
        // user the first time (because NSAppleEventsUsageDescription is set in
        // Info.plist). We dispatch on DispatchQueue.main so the system can present
        // the prompt and so the Apple Events framework runs in the expected context.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let script = NSAppleScript(source: scriptSource)
                var errDict: NSDictionary?
                script?.executeAndReturnError(&errDict)

                if let err = errDict {
                    let msg = (err[NSAppleScript.errorMessage] as? String)
                           ?? (err[NSAppleScript.errorBriefMessage] as? String)
                           ?? err.description
                    continuation.resume(throwing: ExportError.exportFailed(msg))
                    return
                }

                let fm = FileManager.default
                guard fm.fileExists(atPath: pptxURL.path),
                      (try? fm.attributesOfItem(atPath: pptxURL.path)[.size] as? Int ?? 0) ?? 0 > 0
                else {
                    continuation.resume(throwing: ExportError.emptyOutput)
                    return
                }
                continuation.resume(returning: pptxURL.path)
            }
        }
    }

    // MARK: - Private helpers

    private static func resolveURL(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolved.path) { return resolved }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        process.arguments = ["download", url.path]
        try? process.run()
        process.waitUntilExit()

        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 1)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return url
    }

    private static func buildAppleScript(keynotePath: String, pptxPath: String) -> String {
        let ks = keynotePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let ps = pptxPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
tell application id "com.apple.Keynote"
    set targetDoc to open POSIX file "\(ks)"
    repeat 60 times
        try
            if (count of slides of targetDoc) > 0 then exit repeat
        end try
        delay 0.5
    end repeat
    export targetDoc to POSIX file "\(ps)" as Microsoft PowerPoint
    close targetDoc saving no
end tell
"""
    }
}

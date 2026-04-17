// KeynoteExporter.swift
import Foundation

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

        let (appName, appPath) = findKeynoteApp()

        // Pre-launch Keynote
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-a", appPath]
        try? launcher.run()
        try await Task.sleep(for: .seconds(2))

        // Write PPTX to a temp path
        let pptxURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pptx")

        let script = buildAppleScript(keynotePath: resolved.path, pptxPath: pptxURL.path, appName: appName)

        // Write script to a temp file and execute
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("applescript")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [scriptURL.path]

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            // Timeout watchdog
            let deadline = DispatchTime.now() + .seconds(180)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: ExportError.timeout)
                }
            }

            process.terminationHandler = { p in
                if p.terminationStatus != 0 {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: ExportError.exportFailed(errText))
                    return
                }
                guard FileManager.default.fileExists(atPath: pptxURL.path),
                      (try? FileManager.default.attributesOfItem(atPath: pptxURL.path)[.size] as? Int ?? 0) ?? 0 > 0
                else {
                    continuation.resume(throwing: ExportError.emptyOutput)
                    return
                }
                continuation.resume(returning: pptxURL.path)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ExportError.exportFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Private

    private static func resolveURL(_ url: URL) throws -> URL {
        // Try symlink resolution first
        let resolved = url.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolved.path) { return resolved }

        // Try brctl download for iCloud placeholders
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        process.arguments = ["download", url.path]
        try? process.run()
        process.waitUntilExit()

        // Wait up to 10 s for file to materialise
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 1)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        return url
    }

    private static func findKeynoteApp() -> (name: String, path: String) {
        let dirs = ["/Applications", "/System/Applications",
                    NSString("~/Applications").expandingTildeInPath]
        for dir in dirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") && entry.lowercased().contains("keynote") {
                let name = String(entry.dropLast(4)) // strip .app
                return (name, "\(dir)/\(entry)")
            }
        }
        return ("Keynote", "/Applications/Keynote.app")
    }

    private static func buildAppleScript(keynotePath: String, pptxPath: String, appName: String) -> String {
        let ks = keynotePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let ps = pptxPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let name = appName.replacingOccurrences(of: "\"", with: "\\\"")
        return """
tell application "\(name)"
    repeat 30 times
        if running then exit repeat
        delay 0.5
    end repeat
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

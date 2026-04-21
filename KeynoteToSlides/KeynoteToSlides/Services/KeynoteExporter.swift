// KeynoteExporter.swift
import Foundation
import AppKit

// MARK: - Errors

enum ExportError: LocalizedError {
    case fileNotFound(String)
    case keynoteNotFound
    case exportFailed(String)
    case emptyOutput
    case scriptNotInstalled
    case installCancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p):
            return "Keynote file not found: \(p)\n\nIf stored in iCloud, make sure it's fully downloaded first."
        case .keynoteNotFound:
            return "Keynote app not found. Please install Keynote from the App Store."
        case .exportFailed(let msg):
            return "Export failed:\n\(msg)"
        case .emptyOutput:
            return "Export produced no output file. Check that Keynote can open this file."
        case .scriptNotInstalled:
            return "The Keynote export helper script is not installed. Please convert a file to set it up."
        case .installCancelled:
            return "Setup was cancelled. The export helper script is required to convert Keynote files."
        }
    }
}

// MARK: - KeynoteExporter

struct KeynoteExporter {

    // MARK: - Script installation

    /// UserDefaults key storing the security-scoped bookmark for the installed script.
    private static let kScriptBookmark = "KeynoteExportScriptBookmark"

    /// Returns the installed script URL resolved from the stored bookmark, or nil if not yet set up.
    static var installedScriptURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: kScriptBookmark) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        return url
    }

    /// Shows an NSSavePanel so the user can install the bundled export script into the
    /// Application Scripts directory — the ONLY way a sandboxed app can write there.
    /// Saves a security-scoped bookmark so we can open the script in future sessions.
    ///
    /// Must be called on the main actor.
    @MainActor
    static func installScript() async throws {
        // Locate the bundled template script
        guard let bundledURL = Bundle.main.url(forResource: "KeynoteExport", withExtension: "applescript") else {
            throw ExportError.exportFailed("Bundled export script (KeynoteExport.applescript) not found in the app.")
        }

        // Resolve the Application Scripts directory (sandboxed apps have read access here)
        let scriptsDir: URL
        do {
            scriptsDir = try FileManager.default.url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw ExportError.exportFailed("Cannot locate Application Scripts folder: \(error.localizedDescription)")
        }

        // ── Present NSSavePanel ────────────────────────────────────────────────
        // NSSavePanel (the OS "powerbox") is the only mechanism that grants a
        // sandboxed app write access to the Application Scripts directory.
        let panel = NSSavePanel()
        panel.directoryURL          = scriptsDir
        panel.nameFieldStringValue  = "KeynoteExport.applescript"
        panel.canCreateDirectories  = false
        panel.title                 = "Install Keynote Export Helper"
        panel.message               = """
            KeynoteToSlides needs to install a one-time helper script so it can export \
            Keynote presentations. The folder is pre-selected — just click Install.
            """
        panel.prompt = "Install"

        let response = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.begin { r in cont.resume(returning: r) }
        }

        guard response == .OK, let destURL = panel.url else {
            throw ExportError.installCancelled
        }

        // Verify the user didn't navigate away from the scripts directory
        guard destURL.deletingLastPathComponent().standardized == scriptsDir.standardized else {
            throw ExportError.exportFailed(
                "The script must be saved in the pre-selected folder. Please try again without changing the location."
            )
        }

        // Copy the bundled script to the chosen path
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        try fm.copyItem(at: bundledURL, to: destURL)

        // Save a security-scoped bookmark so future sessions can re-open the file
        let bookmark = try destURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: kScriptBookmark)
    }

    // MARK: - Export

    static func export(from fileURL: URL) async throws -> String {
        let resolved = try resolveURL(fileURL)

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw ExportError.fileNotFound(resolved.path)
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Keynote") != nil else {
            throw ExportError.keynoteNotFound
        }

        guard let scriptURL = installedScriptURL else {
            throw ExportError.scriptNotInstalled
        }

        // Output lands in the sandbox-accessible temp directory
        let pptxURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kts_\(UUID().uuidString)")
            .appendingPathExtension("pptx")

        // Open the security-scoped resource before handing it to NSUserAppleScriptTask
        let accessed = scriptURL.startAccessingSecurityScopedResource()
        defer { if accessed { scriptURL.stopAccessingSecurityScopedResource() } }

        // Build the Apple Event: invoke `on run argv` with [keynotePath, pptxPath]
        let event = makeRunEvent(args: [resolved.path, pptxURL.path])

        // NSUserAppleScriptTask runs the script in a separate process OUTSIDE the sandbox,
        // bypassing the scripting-targets restriction on the `export` command.
        let task = try NSUserAppleScriptTask(url: scriptURL)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.execute(withAppleEvent: event) { (_: NSAppleEventDescriptor?, error: Error?) in
                if let error = error {
                    cont.resume(throwing: ExportError.exportFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            }
        }

        // Verify the output file exists and is non-empty
        let fm = FileManager.default
        guard fm.fileExists(atPath: pptxURL.path),
              (try? fm.attributesOfItem(atPath: pptxURL.path)[.size] as? Int) ?? 0 > 0
        else {
            throw ExportError.emptyOutput
        }

        return pptxURL.path
    }

    // MARK: - Private helpers

    /// Constructs an Apple Event that triggers `on run argv` in an AppleScript,
    /// passing the given strings as the direct-object list.
    private static func makeRunEvent(args: [String]) -> NSAppleEventDescriptor {
        // 'aevt'/'oapp' is the standard "run" Apple Event that maps to `on run argv`.
        let kCoreEventClass: AEEventClass = 0x61657674  // 'aevt'
        let kAEOpenApp: AEEventID         = 0x6F617070  // 'oapp'
        let keyDirectObj: AEKeyword       = 0x2D2D2D2D  // '----'

        let event = NSAppleEventDescriptor(
            eventClass: kCoreEventClass,
            eventID: kAEOpenApp,
            targetDescriptor: nil,
            returnID: Int16(bitPattern: UInt16(0xFFFF)), // kAutoGenerateReturnID = -1
            transactionID: 0                             // kAnyTransactionID = 0
        )

        let argList = NSAppleEventDescriptor.list()
        for (i, arg) in args.enumerated() {
            argList.insert(NSAppleEventDescriptor(string: arg), at: i + 1)
        }
        event.setParam(argList, forKeyword: keyDirectObj)
        return event
    }

    private static func resolveURL(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolved.path) { return resolved }

        // Attempt to trigger an iCloud download; failure is non-fatal
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
}

// PythonRunner.swift
// Swift ↔ Python subprocess bridge.
//
// Protocol (mirrors python/cli.py):
//   stdin:  one JSON line  {"command":"…","args":{…}}
//   stdout: N×  {"type":"progress","done":int,"total":int,"message":"…"}
//           1×  {"type":"result", …command-specific fields…}
//            OR {"type":"error","message":"…"}  + exit code 1
//
// Path resolution (three tiers, checked in order):
//   Bundled binary : Contents/Resources/cli  (PyInstaller one-file binary)
//                    → called directly, no Python interpreter needed
//   Bundle + python: Contents/Resources/python-runtime/bin/python3 + cli.py
//                    → legacy embedded-python layout
//   Dev            : /usr/bin/python3 + <repo>/python/cli.py  (via #filePath)

import Foundation

// MARK: - Errors

enum PythonRunnerError: LocalizedError {
    case pythonNotFound
    case cliNotFound
    case encodingFailed
    case decodingFailed(String)
    case pythonError(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python runtime not found. Make sure python3 is installed at /usr/bin/python3."
        case .cliNotFound:
            return "cli.py not found. Check that python/cli.py exists next to the app."
        case .encodingFailed:
            return "Failed to encode the Python request to JSON."
        case .decodingFailed(let msg):
            return "Failed to decode Python response: \(msg)"
        case .pythonError(let msg):
            return msg
        }
    }
}

// MARK: - PythonRunner

/// Runs `python/cli.py` as a subprocess, sends one JSON request on stdin,
/// and streams progress + result events from stdout.
final class PythonRunner: Sendable {

    static let shared = PythonRunner()
    private init() {}

    // MARK: Path resolution

    /// Path to the PyInstaller CLI executable bundled in the app (highest priority).
    /// Supports two layouts produced by the build script:
    ///   onedir (App Store): Contents/Resources/cli/cli   ← preferred
    ///   onefile (legacy):   Contents/Resources/cli        ← fallback
    private var bundledCLIBinaryPath: String? {
        guard let resources = Bundle.main.resourcePath else { return nil }
        // One-directory layout (Mac App Store compatible — all .so files are individually signed)
        let oneDirBin = resources + "/cli/cli"
        if FileManager.default.fileExists(atPath: oneDirBin) { return oneDirBin }
        // One-file layout (notarized direct distribution)
        let oneFileBin = resources + "/cli"
        if FileManager.default.fileExists(atPath: oneFileBin) { return oneFileBin }
        return nil
    }

    /// Path to the Python executable (fallback when no bundled binary exists).
    private var pythonExecutable: String {
        // Bundle path takes priority (embedded python-build-standalone runtime)
        if let resources = Bundle.main.resourcePath {
            let bundlePy = resources + "/python-runtime/bin/python3"
            if FileManager.default.fileExists(atPath: bundlePy) { return bundlePy }
        }
        // Development: use the system python3
        return "/usr/bin/python3"
    }

    /// Path to the cli.py entry point (used when running with a Python interpreter).
    private var cliPath: String {
        // Bundle: Contents/Resources/python/cli.py
        if let resources = Bundle.main.resourcePath {
            let bundleCli = resources + "/python/cli.py"
            if FileManager.default.fileExists(atPath: bundleCli) { return bundleCli }
        }

        // Development: walk up from this source file to find python/cli.py in the repo root.
        // #filePath is the compile-time path of this Swift file:
        //   …/KeynoteToSlides/KeynoteToSlides/PythonRunner.swift
        // Repo root is two levels up.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent()   // KeynoteToSlides/ (sources)
            .deletingLastPathComponent()   // KeynoteToSlides/ (Xcode project folder)
            .deletingLastPathComponent()   // repo root
        let devCli = repoRoot.appendingPathComponent("python/cli.py").path
        return devCli
    }

    /// Environment for the subprocess.
    /// Adds bundled site-packages to PYTHONPATH when running with an interpreter.
    private var subprocessEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let resources = Bundle.main.resourcePath {
            let sp = resources + "/python/site-packages"
            if FileManager.default.fileExists(atPath: sp) {
                let existing = env["PYTHONPATH"] ?? ""
                env["PYTHONPATH"] = existing.isEmpty ? sp : (sp + ":" + existing)
            }
        }
        // Prevent Python from writing .pyc files into the read-only bundle
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return env
    }

    // MARK: Core runner

    /// Run a command and stream progress events until the final result.
    ///
    /// - Parameters:
    ///   - command: One of the commands defined in cli.py.
    ///   - args: JSON-serialisable dictionary of arguments.
    ///   - onProgress: Called on the **main thread** for each progress event.
    /// - Returns: The raw JSON dictionary from the `result` event.
    func run(
        command: String,
        args: [String: Any],
        onProgress: (@Sendable @MainActor (PythonProgress) -> Void)? = nil
    ) async throws -> [String: Any] {

        // Validate paths — bundled binary takes priority over python interpreter
        if bundledCLIBinaryPath == nil {
            guard FileManager.default.fileExists(atPath: pythonExecutable) else {
                throw PythonRunnerError.pythonNotFound
            }
            guard FileManager.default.fileExists(atPath: cliPath) else {
                throw PythonRunnerError.cliNotFound
            }
        }

        // Encode request
        let requestDict: [String: Any] = ["command": command, "args": args]
        let requestData = try JSONSerialization.data(withJSONObject: requestDict)
        guard let requestLine = String(data: requestData, encoding: .utf8) else {
            throw PythonRunnerError.encodingFailed
        }

        // Bridge blocking Process I/O to async Swift
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runBlocking(
                        requestLine: requestLine,
                        onProgress: onProgress
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Blocking execution (runs on a background thread)

    private func _runBlocking(
        requestLine: String,
        onProgress: (@Sendable @MainActor (PythonProgress) -> Void)?
    ) throws -> [String: Any] {

        let process = Process()
        if let binary = bundledCLIBinaryPath {
            // PyInstaller one-file binary — call it directly with no arguments
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments     = []
        } else {
            // Python interpreter + cli.py (dev or legacy bundle layout)
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments     = [cliPath]
        }
        process.environment = subprocessEnvironment

        let stdinPipe  = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput  = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        try process.run()

        // Write JSON request and close stdin so Python's readline() returns
        let inputData = (requestLine + "\n").data(using: .utf8)!
        try stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
        try stdinPipe.fileHandleForWriting.close()

        // Read all stdout (blocking — Python process runs to completion)
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Parse newline-delimited JSON
        let output = String(data: outputData, encoding: .utf8) ?? ""
        var resultDict: [String: Any]? = nil
        var lastErrorMessage: String? = nil

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            switch json["type"] as? String {
            case "progress":
                if let cb = onProgress,
                   let done  = json["done"]    as? Int,
                   let total = json["total"]   as? Int,
                   let msg   = json["message"] as? String {
                    let progress = PythonProgress(done: done, total: total, message: msg)
                    DispatchQueue.main.async { Task { @MainActor in cb(progress) } }
                }

            case "result":
                resultDict = json

            case "error":
                lastErrorMessage = json["message"] as? String ?? "Unknown Python error"

            default:
                break
            }
        }

        if let errMsg = lastErrorMessage {
            throw PythonRunnerError.pythonError(errMsg)
        }

        if process.terminationStatus != 0 && resultDict == nil {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw PythonRunnerError.pythonError(
                "Python exited with code \(process.terminationStatus).\n\(stderrText)"
            )
        }

        guard let result = resultDict else {
            throw PythonRunnerError.decodingFailed("No result event received from cli.py")
        }

        return result
    }

    // MARK: Typed command methods

    /// Scan a PPTX for fonts not supported by Google Slides.
    func checkFonts(pptxPath: String) async throws -> CheckFontsResult {
        let raw = try await run(command: "check_fonts", args: ["pptx_path": pptxPath])
        return try _decode(CheckFontsResult.self, from: raw)
    }

    /// Write a new PPTX with font names substituted.
    func replaceFonts(
        pptxPath: String,
        outputPath: String,
        replacements: [String: String]
    ) async throws -> String {
        let raw = try await run(
            command: "replace_fonts",
            args: [
                "pptx_path":    pptxPath,
                "output_path":  outputPath,
                "replacements": replacements
            ]
        )
        return try _decode(ReplaceFontsResult.self, from: raw).outputPath
    }

    /// Return whether the PPTX has embedded videos and their names.
    func hasVideos(pptxPath: String) async throws -> HasVideosResult {
        let raw = try await run(command: "has_videos", args: ["pptx_path": pptxPath])
        return try _decode(HasVideosResult.self, from: raw)
    }

    func listFonts() async throws -> [String] {
        let raw = try await run(command: "list_fonts", args: [:])
        guard let fonts = raw["fonts"] as? [String] else {
            throw PythonRunnerError.decodingFailed("fonts array missing from list_fonts result")
        }
        return fonts
    }

    /// Recompress images (and optionally strip videos) to meet the 95 MB limit.
    func compressPptx(
        pptxPath: String,
        outputPath: String,
        onProgress: (@Sendable @MainActor (PythonProgress) -> Void)? = nil
    ) async throws -> CompressResult {
        let raw = try await run(
            command: "compress_pptx",
            args: ["pptx_path": pptxPath, "output_path": outputPath],
            onProgress: onProgress
        )
        return try _decode(CompressResult.self, from: raw)
    }

    // MARK: Private helpers

    private func _decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PythonRunnerError.decodingFailed(error.localizedDescription)
        }
    }
}

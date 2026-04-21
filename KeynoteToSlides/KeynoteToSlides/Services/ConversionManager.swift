// ConversionManager.swift
// Extension on AppState that runs the full Keynote → Google Slides pipeline.
import Foundation

extension AppState {

    func startConversion() async {
        guard let fileURL = selectedFileURL else { return }

        var pptxPath: String? = nil
        var fixedPath: String? = nil
        var compressedPath: String? = nil

        defer {
            // Clean up temp files — best effort
            for path in [pptxPath, fixedPath, compressedPath].compactMap({ $0 }) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        do {
            // 0a. One-time setup: install the Keynote export helper script
            //     The sandbox prevents FileManager writes to Application Scripts;
            //     NSSavePanel (powerbox) grants access and saves a security-scoped bookmark.
            if KeynoteExporter.installedScriptURL == nil {
                try await KeynoteExporter.installScript()
            }

            // 0b. Warn that Keynote will open/close automatically
            let proceed: Bool = await withCheckedContinuation { continuation in
                keynoteContinuation = continuation
                showKeynoteWarningSheet = true
            }
            guard proceed else {
                phase = .idle
                return
            }

            // 1. Export Keynote → PPTX
            phase = .exporting
            pptxPath = try await KeynoteExporter.export(from: fileURL)
            var uploadSource = pptxPath!

            // 2. Check fonts
            phase = .checkingFonts
            let fontResult = try await PythonRunner.shared.checkFonts(pptxPath: uploadSource)

            if !fontResult.unsupported.isEmpty {
                // Pause and show font replacement sheet
                let replacements: [String: String]? = await withCheckedContinuation { continuation in
                    fontContinuation = continuation
                    // Deduplicate — the same font can appear in multiple slides/shapes
                    var seen = Set<String>()
                    pendingUnsupportedFonts = fontResult.unsupported.filter { seen.insert($0).inserted }
                    showFontReplacementSheet = true
                }

                guard let replacements else {
                    phase = .idle
                    return  // user cancelled
                }

                // 3. Replace fonts
                if !replacements.isEmpty {
                    phase = .replacingFonts
                    let outPath = NSTemporaryDirectory() + UUID().uuidString + "_fixed.pptx"
                    fixedPath = outPath
                    uploadSource = try await PythonRunner.shared.replaceFonts(
                        pptxPath: uploadSource,
                        outputPath: outPath,
                        replacements: replacements
                    )
                }
            }

            // 4. Check for videos (stripped silently — no user prompt)
            phase = .checkingVideos
            let videoResult = try await PythonRunner.shared.hasVideos(pptxPath: uploadSource)

            // 5. Compress if needed (>95 MB or has videos to strip)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadSource)[.size] as? Int) ?? 0
            let fileMB = Double(fileSize) / 1_048_576

            if fileMB > 95 || videoResult.hasVideos {
                phase = .compressing
                let outPath = NSTemporaryDirectory() + UUID().uuidString + "_compressed.pptx"
                compressedPath = outPath

                let compressResult = try await PythonRunner.shared.compressPptx(
                    pptxPath: uploadSource,
                    outputPath: outPath,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.progressMessage = progress.message
                        }
                    }
                )

                guard compressResult.underLimit else {
                    phase = .failed(message: String(format:
                        "The file is %.0f MB after maximum compression — still above Google's 100 MB limit. "
                        + "Please split the presentation or remove large images.",
                        compressResult.finalMB))
                    return
                }
                uploadSource = outPath
            }

            // 6. Upload
            phase = .uploading
            uploadProgress = 0
            let title = fileURL.deletingPathExtension().lastPathComponent
            let accessToken = try await GoogleAuth.shared.freshAccessToken()

            let slidesURL = try await DriveUploader.upload(
                pptxPath: uploadSource,
                title: title,
                accessToken: accessToken,
                onProgress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.uploadProgress = fraction
                    }
                }
            )

            phase = .done(slidesURL: slidesURL)

        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }
}

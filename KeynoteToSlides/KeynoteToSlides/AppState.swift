// AppState.swift
import Foundation
import SwiftUI

// MARK: - Supporting types

struct UserInfo: Equatable {
    let email: String
    let name: String
    let pictureURL: URL?
}

enum ConversionPhase: Equatable {
    case idle
    case exporting
    case checkingFonts
    case replacingFonts
    case checkingVideos
    case compressing
    case uploading
    case done(slidesURL: URL)
    case failed(message: String)

    var isRunning: Bool {
        switch self {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:             return ""
        case .exporting:        return "Exporting Keynote to PowerPoint…"
        case .checkingFonts:    return "Checking font compatibility…"
        case .replacingFonts:   return "Replacing fonts…"
        case .checkingVideos:   return "Checking for embedded videos…"
        case .compressing:      return "Compressing file…"
        case .uploading:        return "Uploading to Google Drive…"
        case .done:             return "✓  Conversion complete!"
        case .failed(let msg):  return "Error: \(msg)"
        }
    }

    var isError: Bool   { if case .failed = self { return true }; return false }
    var isSuccess: Bool { if case .done   = self { return true }; return false }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // ── File selection ──────────────────────────────────────────────────────
    @Published var selectedFileURL: URL?

    var selectedFileName: String { selectedFileURL?.lastPathComponent ?? "" }
    var selectedFileSizeMB: Double {
        guard let url = selectedFileURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return 0 }
        return Double(size) / 1_048_576
    }

    // ── Auth ────────────────────────────────────────────────────────────────
    @Published var userInfo: UserInfo?
    @Published var isSigningIn: Bool = false

    // ── Font replacements ────────────────────────────────────────────────────
    @Published var savedFontReplacements: [String: String] = [:]
    @Published var cachedFontList: [String] = []

    // ── Conversion pipeline ─────────────────────────────────────────────────
    @Published var phase: ConversionPhase = .idle
    @Published var progressMessage: String = ""
    @Published var uploadProgress: Double = 0

    var canConvert: Bool { selectedFileURL != nil && userInfo != nil && !phase.isRunning }

    // ── Sheet / dialog state ─────────────────────────────────────────────────
    @Published var pendingUnsupportedFonts: [String] = []
    @Published var showFontReplacementSheet: Bool = false
    @Published var pendingVideoNames: [String] = []
    @Published var showVideoWarningSheet: Bool = false

    // Continuation holders — not @Published, used only on MainActor
    var fontContinuation: CheckedContinuation<[String: String]?, Never>?
    var videoContinuation: CheckedContinuation<Bool, Never>?

    // ── Lifecycle ────────────────────────────────────────────────────────────
    init() { loadSavedFontReplacements() }

    // MARK: - Sheet submit methods (called from sheet views)

    func submitFontReplacement(_ replacements: [String: String]?) {
        showFontReplacementSheet = false
        fontContinuation?.resume(returning: replacements)
        fontContinuation = nil
    }

    func submitVideoWarning(proceed: Bool) {
        showVideoWarningSheet = false
        videoContinuation?.resume(returning: proceed)
        videoContinuation = nil
    }

    // MARK: - Font replacement persistence (UserDefaults)

    private let kFontReplacements = "savedFontReplacements"

    func loadSavedFontReplacements() {
        savedFontReplacements =
            UserDefaults.standard.dictionary(forKey: kFontReplacements) as? [String: String] ?? [:]
    }

    func saveFontReplacements(_ replacements: [String: String]) {
        var merged = savedFontReplacements
        merged.merge(replacements) { _, new in new }
        savedFontReplacements = merged
        UserDefaults.standard.set(merged, forKey: kFontReplacements)
    }

    func clearFontReplacements() {
        savedFontReplacements = [:]
        UserDefaults.standard.removeObject(forKey: kFontReplacements)
    }

    var hasSavedFontReplacements: Bool { !savedFontReplacements.isEmpty }

    // MARK: - Font list prefetch

    func prefetchFontList() async {
        guard cachedFontList.isEmpty else { return }
        do {
            cachedFontList = try await PythonRunner.shared.listFonts()
        } catch {
            // Silently fall back — autocomplete will just have no suggestions
        }
    }
}

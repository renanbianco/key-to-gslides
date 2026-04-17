// AppState.swift
// Single source of truth for the entire app, observed by all SwiftUI views.

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
        case .compressing:      return "Compressing…"
        case .uploading:        return "Uploading to Google Drive…"
        case .done:             return "✓  Conversion complete!"
        case .failed(let msg):  return "Error: \(msg)"
        }
    }

    var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    var isSuccess: Bool {
        if case .done = self { return true }
        return false
    }
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

    var isSignedIn: Bool { userInfo != nil }

    // ── Font replacements ────────────────────────────────────────────────────
    /// Saved mapping loaded from UserDefaults: oldFontName → replacementFontName
    @Published var savedFontReplacements: [String: String] = [:]

    // ── Conversion pipeline ─────────────────────────────────────────────────
    @Published var phase: ConversionPhase = .idle
    @Published var progressMessage: String = ""
    @Published var uploadProgress: Double = 0          // 0.0 – 1.0

    var canConvert: Bool { selectedFileURL != nil && isSignedIn && !phase.isRunning }

    // ── Sheet / dialog presentation ──────────────────────────────────────────
    @Published var pendingUnsupportedFonts: [String] = []
    @Published var showFontReplacementSheet: Bool = false
    @Published var pendingVideoNames: [String] = []
    @Published var showVideoWarningSheet: Bool = false

    // ── Lifecycle ────────────────────────────────────────────────────────────

    init() {
        loadSavedFontReplacements()
    }

    // MARK: Font replacement persistence (UserDefaults)

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
}

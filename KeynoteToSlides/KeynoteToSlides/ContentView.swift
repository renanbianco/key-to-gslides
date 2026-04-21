// ContentView.swift
import SwiftUI
import AppKit

// MARK: - Design tokens (shared)

enum DS {
    static let ink      = Color(red: 0.114, green: 0.114, blue: 0.122)   // #1d1d1f
    static let ink2     = Color(red: 0.235, green: 0.235, blue: 0.263)   // #3c3c43
    static let muted    = Color(red: 0.431, green: 0.431, blue: 0.451)   // #6e6e73
    static let mute2    = Color(red: 0.525, green: 0.525, blue: 0.545)   // #86868b
    static let line     = Color.primary.opacity(0.12)
    static let line2    = Color.primary.opacity(0.06)
    static let bg       = Color.white
    static let bg2      = Color(red: 0.961, green: 0.961, blue: 0.969)   // #f5f5f7
    static let bg3      = Color(red: 0.984, green: 0.984, blue: 0.992)   // #fbfbfd
    static let blue     = Color(red: 0.000, green: 0.443, blue: 0.890)   // #0071e3
    static let blueSoft = Color(red: 0.000, green: 0.443, blue: 0.890, opacity: 0.10)
    static let green    = Color(red: 0.122, green: 0.616, blue: 0.333)   // #1f9d55
    static let greenSoft = Color(red: 0.122, green: 0.616, blue: 0.333, opacity: 0.10)
    static let red      = Color(red: 0.784, green: 0.216, blue: 0.176)   // #c8372d
    static let redSoft  = Color(red: 0.784, green: 0.216, blue: 0.176, opacity: 0.08)
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSavedFontsSheet = false

    // Conversion pipeline steps for the segmented progress bar
    private let steps: [(phase: String, label: String)] = [
        ("exporting",      "Exporting Keynote"),
        ("checkingFonts",  "Checking fonts"),
        ("replacingFonts", "Replacing fonts"),
        ("checkingVideos", "Scanning media"),
        ("compressing",    "Compressing"),
        ("uploading",      "Uploading to Drive"),
    ]

    private var currentStepIndex: Int {
        switch appState.phase {
        case .exporting:      return 0
        case .checkingFonts:  return 1
        case .replacingFonts: return 2
        case .checkingVideos: return 3
        case .compressing:    return 4
        case .uploading:      return 5
        default:              return 0
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Main content ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                HeroView()
                Divider()
                AccountBarView(onSignIn: handleSignIn)
                Divider()
                DropZoneView(onPickFile: pickFile)

                if appState.phase.isRunning {
                    progressCard
                }

                if case .done(let url) = appState.phase {
                    doneCard(url: url)
                }

                if case .failed(let msg) = appState.phase {
                    errorCard(message: msg)
                }

                actionButton
                Spacer(minLength: 0)
                utilityBar
            }
            .frame(width: 480)
            .fixedSize(horizontal: true, vertical: true)

            // ── In-window font replacement overlay ───────────────────────────
            if appState.showFontReplacementSheet {
                fontSheetOverlay(for: FontReplacementSheet().environmentObject(appState))
                    .frame(width: 480)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: appState.showFontReplacementSheet)
            }

            // ── In-window Keynote warning overlay ────────────────────────────
            if appState.showKeynoteWarningSheet {
                fontSheetOverlay(for: KeynoteWarningSheet().environmentObject(appState))
                    .frame(width: 480)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: appState.showKeynoteWarningSheet)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .sheet(isPresented: $showSavedFontsSheet) {
            SavedFontsSheet(isPresented: $showSavedFontsSheet).environmentObject(appState)
        }
        .task {
            if let user = try? await GoogleAuth.shared.restoreSession() {
                appState.userInfo = user
            }
            await appState.prefetchFontList()
        }
    }

    // MARK: - In-window modal overlay (shared by font sheet and Keynote warning)

    private func fontSheetOverlay<Content: View>(for card: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Backdrop
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                // Floating card
                card
                    .frame(width: min(geo.size.width * 0.86, 420))
                    .padding(.top, 46)
            }
        }
    }

    // MARK: - Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 13, height: 13)
                Text(steps[currentStepIndex].label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DS.ink)
                    .tracking(-0.05)
                Spacer()
                Text("\(currentStepIndex + 1)/\(steps.count)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.mute2)
                    .monospacedDigit()
            }

            // Segmented step bar
            HStack(spacing: 3) {
                ForEach(0..<steps.count, id: \.self) { i in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < currentStepIndex ? DS.blue : DS.line)
                            .frame(height: 3)

                        if i == currentStepIndex {
                            if case .uploading = appState.phase {
                                // Determinate upload fill
                                GeometryReader { g in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(DS.blue)
                                        .frame(width: g.size.width * appState.uploadProgress)
                                        .animation(.linear(duration: 0.2), value: appState.uploadProgress)
                                }
                                .frame(height: 3)
                            } else {
                                // Indeterminate shimmer
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(DS.blue)
                                    .frame(height: 3)
                                    .opacity(0.7)
                            }
                        }
                    }
                }
            }

            if !appState.progressMessage.isEmpty {
                Text(appState.progressMessage)
                    .font(.system(size: 11))
                    .foregroundColor(DS.muted)
                    .monospacedDigit()
                    .tracking(-0.1)
            }
        }
        .padding(16)
        .background(DS.bg3)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.line, lineWidth: 0.5))
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Done card

    private func doneCard(url: URL) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(DS.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 22, height: 22)
            .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text("Ready in Google Slides")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DS.ink)
                    .tracking(-0.05)
                Text(appState.selectedFileName.replacingOccurrences(of: ".key", with: ""))
                    .font(.system(size: 11))
                    .foregroundColor(DS.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.greenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.green.opacity(0.22), lineWidth: 0.5)
        )
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Error card

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundColor(DS.red)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Conversion failed")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DS.ink)
                    .tracking(-0.05)
                Text(message.isEmpty ? "An unexpected error occurred. Check your connection and try again." : message)
                    .font(.system(size: 11.5))
                    .foregroundColor(DS.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Try again") {
                        appState.phase = .idle
                        appState.uploadProgress = 0
                        Task { await appState.startConversion() }
                    }
                    .buttonStyle(LinkButtonStyle(color: DS.red))

                    Button("Dismiss") {
                        appState.phase = .idle
                        appState.uploadProgress = 0
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.redSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.red.opacity(0.25), lineWidth: 0.5)
        )
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Action button (ghost → filled → open in slides)

    @ViewBuilder
    private var actionButton: some View {
        if case .done(let url) = appState.phase {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text("Open in Google Slides")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(filled: true, tone: DS.green))
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
        } else {
            let label: String = {
                if appState.phase.isRunning { return "Converting…" }
                if appState.userInfo == nil  { return "Sign in to continue" }
                if appState.selectedFileURL == nil { return "Choose a file to continue" }
                return "Convert to Google Slides"
            }()
            Button {
                Task { await appState.startConversion() }
            } label: {
                Text(label)
            }
            .buttonStyle(PrimaryActionButtonStyle(filled: appState.canConvert))
            .disabled(!appState.canConvert)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Utility bar

    private var utilityBar: some View {
        VStack(spacing: 0) {
            // Top row: font replacements + sign out
            HStack {
                Button {
                    showSavedFontsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        HStack(alignment: .lastTextBaseline, spacing: 0.5) {
                            Text("A").font(.system(size: 13))
                            Text("a").font(.system(size: 10))
                        }
                        .foregroundColor(DS.muted)
                        Text("Font replacements\(appState.hasSavedFontReplacements ? " · \(appState.savedFontReplacements.count)" : "")")
                            .font(.system(size: 12))
                            .foregroundColor(DS.muted)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if appState.userInfo != nil {
                    Button("Sign out") { handleSignOut() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(DS.muted)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .frame(minHeight: 34)

            // Info note
            HStack(spacing: 5) {
                Image(systemName: "video.slash")
                    .font(.system(size: 10))
                Text("Videos are not supported.")
                    .font(.system(size: 11))
            }
            .foregroundColor(DS.mute2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(DS.bg2)
        }
        .overlay(
            Rectangle()
                .fill(DS.line2)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select a Keynote presentation"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            appState.selectedFileURL = url
            appState.phase = .idle
            appState.uploadProgress = 0
        }
    }

    private func handleSignIn() {
        appState.isSigningIn = true
        Task {
            do {
                let user = try await GoogleAuth.shared.signIn()
                appState.userInfo = user
            } catch {
                appState.phase = .failed(message: error.localizedDescription)
            }
            appState.isSigningIn = false
        }
    }

    private func handleSignOut() {
        Task {
            await GoogleAuth.shared.signOut()
            appState.userInfo = nil
            appState.phase = .idle
            appState.uploadProgress = 0
        }
    }
}

// MARK: - Button styles

/// Ghost (outlined) when not ready; filled blue/green when active.
struct PrimaryActionButtonStyle: ButtonStyle {
    var filled: Bool = true
    var tone: Color = DS.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(-0.08)
            .foregroundColor(filled ? .white : DS.mute2)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(filled ? tone : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        filled ? Color.clear : Color.primary.opacity(0.25),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: filled ? tone.opacity(0.20) : .clear,
                radius: 4, y: 2
            )
            .scaleEffect(configuration.isPressed && filled ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Plain text link button (mirrors LinkButton from the design).
struct LinkButtonStyle: ButtonStyle {
    var color: Color = DS.muted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundColor(configuration.isPressed ? DS.ink : color)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}

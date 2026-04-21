// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSavedFonts = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Google account bar ───────────────────────────────────────────
            AccountBarView(onSignIn: signIn)

            Divider()

            // ── Hero banner ──────────────────────────────────────────────────
            HeroView()

            Divider()

            // ── Drop / pick zone ─────────────────────────────────────────────
            DropZoneView(onPickFile: pickFile)

            // ── Status message / upload progress ────────────────────────────
            if case .uploading = appState.phase {
                VStack(spacing: 6) {
                    ProgressView(value: appState.uploadProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 32)
                    Text(appState.phase.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if !appState.phase.statusMessage.isEmpty {
                Text(appState.phase.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(appState.phase.isError ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
            }

            // ── Primary action button ────────────────────────────────────────
            if case .done(let url) = appState.phase {
                VStack(spacing: 8) {
                    Button("Open in Google Slides") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                    Button("Convert another") {
                        appState.phase = .idle
                        appState.selectedFileURL = nil
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            } else if case .failed = appState.phase {
                HStack(spacing: 12) {
                    Button("Try again")  { appState.phase = .idle }
                    Button("Dismiss")    { appState.phase = .idle; appState.selectedFileURL = nil }
                }
                .padding(.bottom, 16)
            } else {
                Button(action: convert) {
                    if appState.phase.isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Converting…")
                        }
                    } else {
                        Text("Convert to Google Slides")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canConvert)
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            // ── Utility bar ──────────────────────────────────────────────────
            // Saved fonts button hidden until SavedFontsSheet design system is wired up
        }
        .frame(minWidth: 480, minHeight: 380)

        // ── Sheets ───────────────────────────────────────────────────────────
        .sheet(isPresented: $appState.showFontReplacementSheet) {
            FontReplacementSheet()
        }
        .sheet(isPresented: $appState.showVideoWarningSheet) {
            VideoWarningSheet()
        }
        .task { await appState.prefetchFontList() }
    }

    // MARK: - Actions

    private func signIn() {
        Task {
            appState.isSigningIn = true
            defer { appState.isSigningIn = false }
            do {
                let info = try await GoogleAuth.shared.signIn()
                appState.userInfo = info
            } catch {
                // User cancelled or auth failed — no extra UI needed
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "key")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Keynote presentation"
        if panel.runModal() == .OK, let url = panel.url {
            appState.selectedFileURL = url
            appState.phase = .idle
        }
    }

    private func convert() {
        Task { await appState.startConversion() }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

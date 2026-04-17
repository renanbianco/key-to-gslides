// FontReplacementSheet.swift
import SwiftUI

// MARK: - Font name resolver (mirrors python/src/ui/font_dialog.py _resolve_font_name)
private func resolveFont(_ typed: String, fontList: [String]) -> String {
    let t = typed.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return "Arial" }
    let tl = t.lowercased()

    // 1. Exact case-insensitive match
    if let match = fontList.first(where: { $0.lowercased() == tl }) { return match }

    // 2. Unique prefix
    let starts = fontList.filter { $0.lowercased().hasPrefix(tl) }
    if starts.count == 1 { return starts[0] }

    // 3. Unique contains
    let contains = fontList.filter { $0.lowercased().contains(tl) }
    if contains.count == 1 { return contains[0] }

    return t
}

// MARK: - AutocompleteField

struct AutocompleteField: View {
    @Binding var text: String
    let fontList: [String]

    @State private var filtered: [String] = []
    @State private var showPopover = false

    var body: some View {
        TextField("Font name…", text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { new in
                let q = new.lowercased().trimmingCharacters(in: .whitespaces)
                filtered = q.isEmpty ? [] : Array(fontList.filter { $0.lowercased().contains(q) }.prefix(12))
                showPopover = !filtered.isEmpty
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { font in
                            Button {
                                text = font
                                showPopover = false
                            } label: {
                                Text(font)
                                    .font(.custom(font, size: 13))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color(.windowBackgroundColor))
                            if font != filtered.last { Divider() }
                        }
                    }
                }
                .frame(width: 260, height: min(CGFloat(filtered.count) * 33, 300))
            }
    }
}

// MARK: - FontRowView

private struct FontRowView: View {
    let fontName: String
    @Binding var replacement: String
    let fontList: [String]

    var body: some View {
        HStack(spacing: 16) {
            Text(fontName)
                .font(.custom(fontName, size: 15))
                .lineLimit(1)
                .frame(width: 280, alignment: .leading)

            AutocompleteField(text: $replacement, fontList: fontList)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
    }
}

// MARK: - FontReplacementSheet

struct FontReplacementSheet: View {
    @EnvironmentObject var appState: AppState

    @State private var replacements: [String: String] = [:]
    @State private var replaceAllText: String = ""
    @State private var saveForFuture: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Some fonts need replacing")
                    .font(.title2.bold())
                Text("Type any Google Font name or pick from the list. Whatever you type will be used.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            // Replace ALL strip
            HStack(spacing: 12) {
                Text("Replace ALL with one font:")
                    .font(.system(size: 13, weight: .semibold))
                AutocompleteField(text: $replaceAllText, fontList: appState.cachedFontList)
                    .frame(width: 200)
                Button("Apply to all") { applyToAll() }
                    .disabled(replaceAllText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.windowBackgroundColor).opacity(0.5))

            Divider()

            // Column headers
            HStack {
                Text("Font in your presentation")
                    .frame(width: 280, alignment: .leading)
                Text("Replace with (type any Google Font name)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            Divider()

            // Rows
            let maxH = CGFloat(min(appState.pendingUnsupportedFonts.count, 8)) * 57
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.pendingUnsupportedFonts, id: \.self) { font in
                        FontRowView(
                            fontName: font,
                            replacement: Binding(
                                get: { replacements[font] ?? "Arial" },
                                set: { replacements[font] = $0 }
                            ),
                            fontList: appState.cachedFontList
                        )
                        Divider()
                    }
                }
            }
            .frame(height: maxH)

            Divider()

            // Footer
            HStack {
                Toggle("Remember for future conversions", isOn: $saveForFuture)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
                Button("Cancel", role: .cancel) {
                    appState.submitFontReplacement(nil)
                }
                Button("Apply & Convert") { confirm() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(width: 800)
        .onAppear { setup() }
    }

    private func setup() {
        saveForFuture = appState.hasSavedFontReplacements
        replacements = Dictionary(uniqueKeysWithValues: appState.pendingUnsupportedFonts.map { font in
            (font, appState.savedFontReplacements[font] ?? "Arial")
        })
    }

    private func applyToAll() {
        let resolved = resolveFont(replaceAllText, fontList: appState.cachedFontList)
        replaceAllText = resolved
        for font in appState.pendingUnsupportedFonts {
            replacements[font] = resolved
        }
    }

    private func confirm() {
        var resolved: [String: String] = [:]
        for font in appState.pendingUnsupportedFonts {
            resolved[font] = resolveFont(replacements[font] ?? "Arial", fontList: appState.cachedFontList)
        }
        if saveForFuture { appState.saveFontReplacements(resolved) }
        appState.submitFontReplacement(resolved)
    }
}

#Preview {
    let state = AppState()
    state.pendingUnsupportedFonts = ["Futura PT", "Brandon Grotesque", "Gotham"]
    state.cachedFontList = ["Arial", "Montserrat", "Raleway", "Inter", "Roboto", "Lato"]
    return FontReplacementSheet().environmentObject(state)
}

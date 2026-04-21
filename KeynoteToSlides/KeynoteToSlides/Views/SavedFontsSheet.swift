// SavedFontsSheet.swift
//
// Presented as a native .sheet from ContentView.
// Styled to match FontReplacementSheet (compact, DS tokens).

import SwiftUI

struct SavedFontsSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var edited: [String: String] = [:]
    @State private var showResetConfirm = false

    private var sortedKeys: [String] { edited.keys.sorted() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if edited.isEmpty {
                emptyState
            } else {
                fontList
                helpNote
            }
            Divider()
            footer
        }
        .background(DS.bg)
        .frame(width: 420)
        .onAppear { edited = appState.savedFontReplacements }
        .alert("Reset all saved replacements?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                appState.clearFontReplacements()
                edited = [:]
            }
        } message: {
            Text("This will forget all saved font choices. You will be asked again next time an unsupported font is found.")
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saved Font Replacements")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(DS.ink)
                .tracking(-0.15)
            Text("Edit or remove replacements stored from previous conversions.")
                .font(.system(size: 11.5))
                .foregroundColor(DS.muted)
                .tracking(-0.05)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var fontList: some View {
        let visibleRows = min(sortedKeys.count, 6)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedKeys, id: \.self) { font in
                    HStack(spacing: 0) {
                        FontRowView(
                            fontName: font,
                            replacement: Binding(
                                get: { edited[font] ?? googleFontRecommendation(for: font) },
                                set: { edited[font] = $0 }
                            ),
                            fontList: googleSlidesDefaultFonts,
                            extendedFontList: googleFontsResolutionList + appState.cachedFontList,
                            recommendedFont: googleFontRecommendationIfKnown(for: font)
                        )

                        Button("Delete") {
                            edited.removeValue(forKey: font)
                        }
                        .buttonStyle(LinkButtonStyle(color: DS.red))
                        .padding(.trailing, 14)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: CGFloat(visibleRows) * 54)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 32))
                .foregroundColor(DS.mute2)
            Text("No saved replacements yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.muted)
            Text("Font choices you save during a conversion will appear here.")
                .font(.system(size: 11.5))
                .foregroundColor(DS.mute2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var helpNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(DS.mute2)
            Text("You can also write the name of any font available in Google Fonts if you have them enabled on your account.")
                .font(.system(size: 11))
                .foregroundColor(DS.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.bg3)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                showResetConfirm = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("Reset all")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(edited.isEmpty ? DS.mute2.opacity(0.5) : DS.red)
            .disabled(edited.isEmpty)

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(SmallOutlineButtonStyle())

            Button("Save") { commit() }
                .buttonStyle(PrimaryActionButtonStyle(filled: true))
                .frame(width: 80)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg3)
    }

    // MARK: - Actions

    private func commit() {
        appState.setFontReplacements(edited)
        isPresented = false
    }
}

#Preview {
    let state = AppState()
    state.savedFontReplacements = [
        "Futura PT": "Jost",
        "Brandon Grotesque": "DM Sans",
        "Gotham": "Montserrat",
    ]
    state.cachedFontList = ["Arial", "Montserrat", "Raleway", "Inter", "Roboto", "Lato", "Jost", "DM Sans"]
    return SavedFontsSheet(isPresented: .constant(true)).environmentObject(state)
}

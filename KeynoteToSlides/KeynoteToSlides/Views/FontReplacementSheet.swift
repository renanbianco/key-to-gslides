// FontReplacementSheet.swift
//
// Rendered as an in-window overlay by ContentView (not as a SwiftUI .sheet).
// Matches the "compact list" variant from the design handoff.

import SwiftUI

// MARK: - Google Fonts recommendation lookup
// Source: macOS-Fonts-Google-Substitutes.xlsx

private let googleFontMap: [String: String] = [
    // System & UI
    "sf pro": "Inter", "sf pro display": "Inter", "sf pro text": "Inter",
    "sf pro rounded": "Nunito", "sf mono": "JetBrains Mono",
    "sf compact": "Inter", "new york": "DM Serif Display",
    // Sans-Serif
    "helvetica": "Inter", "helvetica neue": "Inter",
    "arial": "Roboto", "arial black": "Roboto", "arial narrow": "Roboto Condensed",
    "arial rounded mt bold": "Nunito",
    "avenir": "Nunito Sans", "avenir next": "Nunito Sans",
    "avenir next condensed": "Barlow Condensed",
    "futura": "Jost", "futura pt": "Jost", "futura pt condensed": "Jost",
    "geneva": "Open Sans", "gill sans": "Lato", "gill sans mt": "Lato",
    "lucida grande": "Open Sans", "optima": "Noto Sans",
    "trebuchet ms": "Source Sans 3", "verdana": "Open Sans",
    "din alternate": "Archivo", "din condensed": "Oswald",
    "graphik": "DM Sans", "galvji": "Inter",
    "founders grotesk": "Space Grotesk",
    "founders grotesk condensed": "Barlow Condensed",
    // Common third-party (not in table but frequent in Keynote)
    "gotham": "Montserrat", "gotham rounded": "Nunito",
    "brandon grotesque": "DM Sans", "brandon text": "DM Sans",
    "proxima nova": "Nunito Sans", "proxima nova condensed": "Barlow Condensed",
    "circular": "Nunito", "circular std": "Nunito",
    "akzidenz grotesk": "Inter",
    "trade gothic": "Oswald", "trade gothic next": "Oswald",
    "univers": "Inter",
    "myriad pro": "Source Sans 3",
    // Serif
    "baskerville": "Libre Baskerville",
    "big caslon": "Libre Caslon Display",
    "bodoni": "Libre Bodoni", "bodoni 72": "Libre Bodoni",
    "canela": "Playfair Display",
    "charter": "Bitter", "cochin": "Cormorant",
    "didot": "Playfair Display",
    "domaine display": "Playfair Display",
    "garamond": "EB Garamond", "apple garamond": "EB Garamond",
    "georgia": "Libre Baskerville",
    "hoefler text": "Crimson Pro",
    "palatino": "Lora",
    "times new roman": "Libre Baskerville",
    "minion pro": "Lora",
    "caslon": "Libre Caslon Display",
    // Slab Serif
    "american typewriter": "Zilla Slab",
    "rockwell": "Arvo", "clarendon": "Zilla Slab",
    "courier new": "Courier Prime", "courier": "Courier Prime",
    // Display
    "copperplate": "Cinzel", "herculanum": "Uncial Antiqua",
    "impact": "Oswald",
    "phosphate": "Bebas Neue", "trajan": "Cinzel",
    // Script
    "apple chancery": "Dancing Script",
    "bradley hand": "Caveat",
    "brush script mt": "Sacramento",
    "chalkboard": "Patrick Hand", "chalkboard se": "Patrick Hand",
    "chalkduster": "Permanent Marker",
    "noteworthy": "Indie Flower",
    "snell roundhand": "Dancing Script",
]

// MARK: - Full Google Fonts resolution list
//
// Mirrors Python's GOOGLE_SLIDES_FONTS set plus all recommendation targets.
// Used ONLY for resolving typed names (e.g. "tenor" → "Tenor Sans").
// NOT shown as the default dropdown — that uses googleSlidesDefaultFonts below.
let googleFontsResolutionList: [String] = [
    "Abel", "Abril Fatface", "Alata", "Alegreya", "Alegreya Sans", "Alegreya SC",
    "Amatic SC", "Anton",
    "Archivo", "Archivo Black", "Archivo Narrow",
    "Arial", "Arial Black", "Arial Narrow", "Arial Rounded MT Bold",
    "Arimo", "Arvo", "Asap", "Assistant",
    "Barlow", "Barlow Condensed", "Barlow Semi Condensed",
    "Bebas Neue", "BioRhyme", "Bitter", "Bodoni Moda", "Brygada 1918",
    "Cabin", "Cabin Condensed", "Cairo", "Calibri", "Cambria", "Candara",
    "Cardo", "Caveat", "Caveat Brush", "Century Gothic",
    "Chivo", "Cinzel", "Cinzel Decorative",
    "Comic Sans MS", "Comfortaa", "Consolas", "Constantia", "Corbel",
    "Cormorant", "Cormorant Garamond",
    "Courier New", "Courier Prime",
    "Crimson Pro", "Crimson Text",
    "Dancing Script", "Didact Gothic", "Domine", "Dosis",
    "DM Mono", "DM Sans", "DM Serif Display", "DM Serif Text",
    "Droid Sans", "Droid Serif", "Droid Sans Mono",
    "EB Garamond", "Epilogue", "Exo", "Exo 2",
    "Figtree", "Fira Code", "Fira Mono", "Fira Sans", "Fira Sans Condensed",
    "Fjalla One", "Frank Ruhl Libre", "Fraunces",
    "Gelasio", "Gentium Basic", "Gentium Book Basic", "Georgia",
    "Gloock", "Gothic A1",
    "Hahmlet", "Hanken Grotesk", "Heebo", "Hedvig Letters Serif",
    "IBM Plex Mono", "IBM Plex Sans", "IBM Plex Serif",
    "Impact", "Inconsolata", "Indie Flower", "Instrument Sans", "Instrument Serif",
    "Inter",
    "JetBrains Mono", "Josefin Sans", "Josefin Slab", "Jost",
    "Kalam", "Kanit", "Karla",
    "Lato", "League Spartan",
    "Lexend", "Lexend Deca", "Lexend Exa", "Lexend Giga",
    "Libre Baskerville", "Libre Bodoni", "Libre Caslon Display", "Libre Franklin",
    "Limelight", "Literata", "Lobster", "Lora",
    "Lucida Console", "Lucida Sans Unicode",
    "Mada", "Manrope", "Material Icons", "Maven Pro",
    "Merriweather", "Merriweather Sans",
    "Microsoft Sans Serif", "Montserrat", "Muli", "Mulish",
    "Nanum Gothic", "Nanum Myeongjo",
    "Noto Mono", "Noto Sans", "Noto Serif",
    "Nunito", "Nunito Sans",
    "Open Sans", "Open Sans Condensed", "Oswald", "Outfit", "Overpass", "Overpass Mono",
    "Oxygen", "Oxygen Mono",
    "Pacifico", "Palatino Linotype", "Patrick Hand", "Permanent Marker",
    "Playfair Display", "Playfair Display SC",
    "Plus Jakarta Sans", "Podkova", "Poppins", "Prompt",
    "PT Sans", "PT Sans Caption", "PT Sans Narrow", "PT Serif",
    "Public Sans",
    "Questrial", "Quicksand",
    "Raleway", "Rasa", "Readex Pro",
    "Red Hat Display", "Red Hat Text", "Righteous", "Rokkitt",
    "Roboto", "Roboto Condensed", "Roboto Mono", "Roboto Slab",
    "Rubik", "Rubik Mono One",
    "Sacramento", "Sarabun", "Signika", "Signika Negative", "Sora",
    "Source Code Pro", "Source Sans 3", "Source Sans Pro", "Source Serif 4", "Source Serif Pro",
    "Space Grotesk", "Space Mono", "Spectral", "Syne",
    "Tahoma", "Teko", "Tenor Sans", "Times New Roman", "Tinos", "Titillium Web",
    "Trebuchet MS",
    "Ubuntu", "Ubuntu Condensed", "Ubuntu Mono", "Uncial Antiqua", "Urbanist",
    "Varela Round", "Verdana", "Vollkorn",
    "Webdings", "Wingdings", "Wix Madefor Display", "Wix Madefor Text", "Work Sans",
    "Yanone Kaffeesatz", "Yrsa", "Ysabeau", "Ysabeau SC",
    "Zilla Slab",
]

// MARK: - Google Slides built-in font list

/// Curated list of fonts available by default in Google Slides.
/// Used as the dropdown source in both font-replacement sheets.
let googleSlidesDefaultFonts: [String] = [
    "Abel", "Abril Fatface", "Amatic SC", "Anton",
    "Archivo", "Archivo Black", "Archivo Narrow",
    "Arial", "Arial Black", "Arial Narrow",
    "Arimo", "Arvo", "Asap",
    "Barlow", "Barlow Condensed", "Barlow Semi Condensed",
    "Bebas Neue", "Bitter",
    "Cabin", "Cairo", "Caveat", "Cinzel",
    "Comfortaa", "Comic Sans MS", "Courier New",
    "Crimson Pro", "Crimson Text",
    "Dancing Script",
    "DM Mono", "DM Sans", "DM Serif Display", "DM Serif Text",
    "Domine", "Dosis",
    "EB Garamond", "Exo 2",
    "Fira Code", "Fira Sans", "Fira Sans Condensed",
    "Fjalla One", "Fraunces",
    "Georgia",
    "Heebo",
    "IBM Plex Mono", "IBM Plex Sans", "IBM Plex Serif",
    "Impact", "Inconsolata", "Indie Flower", "Inter",
    "Josefin Sans", "Josefin Slab", "Jost",
    "Kalam", "Kanit", "Karla",
    "Lato", "League Spartan",
    "Libre Baskerville", "Libre Bodoni", "Libre Franklin",
    "Lobster", "Lora",
    "Manrope", "Maven Pro",
    "Merriweather", "Merriweather Sans",
    "Montserrat", "Mulish",
    "Noto Sans", "Noto Serif", "Nunito", "Nunito Sans",
    "Open Sans", "Oswald", "Outfit",
    "Pacifico", "Patrick Hand", "Permanent Marker",
    "Playfair Display", "Plus Jakarta Sans",
    "Poppins", "PT Sans", "PT Serif",
    "Quicksand",
    "Raleway",
    "Roboto", "Roboto Condensed", "Roboto Mono", "Roboto Slab",
    "Rubik",
    "Sacramento",
    "Source Code Pro", "Source Sans 3", "Source Serif 4",
    "Space Grotesk", "Space Mono", "Spectral", "Syne",
    "Times New Roman", "Tinos", "Titillium Web", "Trebuchet MS",
    "Ubuntu", "Ubuntu Mono", "Urbanist",
    "Verdana",
    "Work Sans",
    "Yanone Kaffeesatz", "Yrsa",
    "Zilla Slab",
]

/// Returns the recommended Google Fonts substitute, or nil if the font has no known mapping.
/// Use this for the "Recommended:" hint label so it only appears when there's a real match.
func googleFontRecommendationIfKnown(for fontName: String) -> String? {
    let key = normalizedFontKey(fontName)
    if let hit = googleFontMap[key] { return hit }
    let sorted = googleFontMap.keys.sorted { $0.count > $1.count }
    for mapKey in sorted {
        if key.contains(mapKey) || mapKey.contains(key) { return googleFontMap[mapKey]! }
    }
    return nil
}

/// Returns the recommended Google Fonts substitute for a given macOS/third-party font.
/// Falls back to "Inter" when no mapping is found.
/// Used for pre-filling the replacement text field.
func googleFontRecommendation(for fontName: String) -> String {
    return googleFontRecommendationIfKnown(for: fontName) ?? "Inter"
}

private func normalizedFontKey(_ fontName: String) -> String {
    fontName
        .lowercased()
        .replacingOccurrences(of: #"\s*(bold|light|thin|medium|semibold|semi bold|italic|regular|black|condensed)\s*$"#,
                              with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

// MARK: - Font name resolver

/// Resolves a typed font name to its correctly-cased form.
/// Searches `primaryList` first, then `fallbackList` (e.g. the full cached Google Fonts list).
/// If nothing matches, returns the trimmed typed value as-is so custom font names still work.
func resolveFont(_ typed: String, primaryList: [String], fallbackList: [String] = []) -> String {
    let t = typed.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return "Arial" }
    let tl = t.lowercased()

    for list in [primaryList, fallbackList] {
        if let exact = list.first(where: { $0.lowercased() == tl }) { return exact }
        let starts = list.filter { $0.lowercased().hasPrefix(tl) }
        if starts.count == 1 { return starts[0] }
        let contains = list.filter { $0.lowercased().contains(tl) }
        if contains.count == 1 { return contains[0] }
    }
    return t
}

// MARK: - Autocomplete / dropdown field

struct AutocompleteField: View {
    @Binding var text: String
    let fontList: [String]
    /// Searched only when `fontList` produces no matches for the current query.
    /// Lets users type "tenor" and see "Tenor Sans" even though it's not in the default dropdown.
    var extendedFontList: [String] = []

    @State private var filtered: [String] = []
    @State private var showPopover = false
    @FocusState private var isFocused: Bool
    @ObservedObject private var fontLoader = FontLoader.shared

    var body: some View {
        TextField("Font name…", text: $text)
            .font(.system(size: 11.5))
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onChange(of: text) { _ in refilter() }
            .onChange(of: isFocused) { _ in
                if isFocused {
                    refilter()
                    showPopover = !filtered.isEmpty
                }
            }
            // Chevron button — opens full list without clearing the field
            .overlay(alignment: .trailing) {
                Button {
                    if showPopover {
                        showPopover = false
                    } else {
                        filtered = fontList
                        showPopover = true
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.mute2)
                        .rotationEffect(showPopover ? .degrees(180) : .zero)
                        .animation(.easeInOut(duration: 0.15), value: showPopover)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
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
                                    .font(.custom(font, size: 12))
                                    // Re-create the Text node once the font finishes loading
                                    .id(fontLoader.loadedFamilies.contains(font))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color(.windowBackgroundColor))
                            // Kick off download the moment this row becomes visible
                            .onAppear { fontLoader.load(font) }
                            if font != filtered.last { Divider() }
                        }
                    }
                }
                .frame(width: 220, height: min(CGFloat(filtered.count) * 30, 260))
            }
    }

    private func refilter() {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            filtered = fontList
        } else {
            let primary = fontList.filter { $0.lowercased().contains(q) }
            if primary.isEmpty && !extendedFontList.isEmpty {
                // No matches in the curated dropdown — search the full known-fonts list
                filtered = extendedFontList.filter { $0.lowercased().contains(q) }
            } else {
                filtered = primary
            }
        }
        if isFocused { showPopover = !filtered.isEmpty }
    }
}

// MARK: - Font row

struct FontRowView: View {
    let fontName: String
    @Binding var replacement: String
    let fontList: [String]
    var extendedFontList: [String] = []
    /// When set, shows a "Recommended: X" hint below the font name.
    var recommendedFont: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Font name + optional recommendation hint
            VStack(alignment: .leading, spacing: 2) {
                Text(fontName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DS.ink)
                    .tracking(-0.05)
                    .lineLimit(1)
                if let rec = recommendedFont {
                    Text("Recommended: \(rec)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.muted)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(DS.mute2)

            AutocompleteField(text: $replacement, fontList: fontList, extendedFontList: extendedFontList)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

// MARK: - FontReplacementSheet

struct FontReplacementSheet: View {
    @EnvironmentObject var appState: AppState

    @State private var replacements: [String: String] = [:]
    @State private var saveForFuture: Bool = false
    @State private var replaceAllText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            replaceAllRow
            Divider()
            fontList
            helpNote
            Divider()
            footer
        }
        .background(DS.bg)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.28), radius: 25, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .onAppear { setup() }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Replace \(appState.pendingUnsupportedFonts.count) unsupported font\(appState.pendingUnsupportedFonts.count == 1 ? "" : "s")")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(DS.ink)
                .tracking(-0.15)
            Text("Google Slides can't render these. Pick a substitute for each.")
                .font(.system(size: 11.5))
                .foregroundColor(DS.muted)
                .tracking(-0.05)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // Replace All row: one shared field + apply button
    private var replaceAllRow: some View {
        HStack(spacing: 8) {
            Text("Replace all")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.ink)
                .fixedSize()

            AutocompleteField(text: $replaceAllText,
                              fontList: googleSlidesDefaultFonts,
                              extendedFontList: googleFontsResolutionList + appState.cachedFontList)

            Button {
                let resolved = resolveFont(replaceAllText,
                                           primaryList: googleSlidesDefaultFonts,
                                           fallbackList: googleFontsResolutionList + appState.cachedFontList)
                applyToAll(resolved)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(SmallOutlineButtonStyle())
            .disabled(replaceAllText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DS.bg3)
    }

    // Sorted unique font names derived from replacements (populated in setup).
    // Driving ForEach from this instead of pendingUnsupportedFonts prevents
    // duplicate-ID crashes when the same font appears more than once in the PPTX.
    private var sortedFontKeys: [String] { replacements.keys.sorted() }

    private var fontList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedFontKeys, id: \.self) { font in
                    FontRowView(
                        fontName: font,
                        replacement: Binding(
                            get: { replacements[font] ?? googleFontRecommendation(for: font) },
                            set: { replacements[font] = $0 }
                        ),
                        fontList: googleSlidesDefaultFonts,
                        extendedFontList: googleFontsResolutionList + appState.cachedFontList,
                        recommendedFont: googleFontRecommendationIfKnown(for: font)
                    )
                    Divider()
                }
            }
        }
        .frame(maxHeight: CGFloat(min(sortedFontKeys.count, 6)) * 54)
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
            Toggle("Remember", isOn: $saveForFuture)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundColor(DS.muted)

            Spacer()

            Button("Cancel", role: .cancel) {
                appState.submitFontReplacement(nil)
            }
            .buttonStyle(SmallOutlineButtonStyle())

            Button("Apply & Convert") { confirm() }
                .buttonStyle(PrimaryActionButtonStyle(filled: true))
                .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg3)
    }

    // MARK: Actions

    private func setup() {
        saveForFuture = appState.hasSavedFontReplacements
        // Deduplicate first — Dictionary(uniqueKeysWithValues:) traps on duplicate keys,
        // and a single Keynote file can legitimately list the same font more than once.
        var seen = Set<String>()
        let uniqueFonts = appState.pendingUnsupportedFonts.filter { seen.insert($0).inserted }
        replacements = Dictionary(uniqueKeysWithValues: uniqueFonts.map { font in
            (font, appState.savedFontReplacements[font] ?? googleFontRecommendation(for: font))
        })
    }

    /// Applies one specific font to every row (used by the Replace All field).
    private func applyToAll(_ font: String) {
        for key in replacements.keys {
            replacements[key] = font
        }
    }

    /// Applies the per-font Google Fonts recommendation to every row.
    private func applyRecommendations() {
        for font in replacements.keys {
            replacements[font] = googleFontRecommendation(for: font)
        }
    }

    private func confirm() {
        // Build the resolved map from replacements (already deduplicated) rather than
        // pendingUnsupportedFonts to avoid any remaining duplicate-key risk.
        // Resolution order: curated dropdown → full known-fonts list → live Python cache.
        // This ensures "tenor" → "Tenor Sans" even when Python hasn't responded yet.
        let resolutionFallback = googleFontsResolutionList + appState.cachedFontList
        var resolved: [String: String] = [:]
        for font in replacements.keys {
            resolved[font] = resolveFont(replacements[font] ?? "Arial",
                                         primaryList: googleSlidesDefaultFonts,
                                         fallbackList: resolutionFallback)
        }
        if saveForFuture { appState.saveFontReplacements(resolved) }
        appState.submitFontReplacement(resolved)
    }
}

// MARK: - Quick-set pill button style

private struct QuickSetPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5))
            .foregroundColor(DS.ink2)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(DS.bg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.line, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    let state = AppState()
    state.pendingUnsupportedFonts = ["Futura PT", "Brandon Grotesque", "Gotham"]
    state.cachedFontList = ["Arial", "Montserrat", "Raleway", "Inter", "Roboto", "Lato"]
    return ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        FontReplacementSheet()
            .environmentObject(state)
            .frame(width: 420)
            .padding(.top, 46)
    }
    .frame(width: 480, height: 500)
}

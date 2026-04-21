// VideoWarningSheet.swift
// Repurposed as the "Keynote will open automatically" heads-up shown before conversion starts.
// Rendered as an in-window overlay by ContentView (same pattern as FontReplacementSheet).

import SwiftUI

struct KeynoteWarningSheet: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageBody
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Keynote will open automatically")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(DS.ink)
                .tracking(-0.15)
            Text("The app needs to control Keynote to export your presentation.")
                .font(.system(size: 11.5))
                .foregroundColor(DS.muted)
                .tracking(-0.05)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var messageBody: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(DS.blue)
                .padding(.top, 1)
            Text("Keynote may open and close on its own during the export. Please don't interact with it or switch windows until the conversion is complete.")
                .font(.system(size: 12))
                .foregroundColor(DS.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") {
                appState.submitKeynoteWarning(proceed: false)
            }
            .buttonStyle(SmallOutlineButtonStyle())

            Button("Start converting") {
                appState.submitKeynoteWarning(proceed: true)
            }
            .buttonStyle(PrimaryActionButtonStyle(filled: true))
            .frame(width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg3)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.28).ignoresSafeArea()
        KeynoteWarningSheet()
            .environmentObject(AppState())
            .frame(width: 420)
            .padding(.top, 46)
    }
    .frame(width: 480, height: 400)
}

// VideoWarningSheet.swift
import SwiftUI

struct VideoWarningSheet: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .padding(.top, 8)

            Text("Embedded videos detected")
                .font(.title2.bold())

            Text("Google Slides doesn't support embedded video import. \(appState.pendingVideoNames.count) video(s) will be removed to allow conversion.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)

            if !appState.pendingVideoNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(appState.pendingVideoNames.prefix(5)), id: \.self) { name in
                        Label(name, systemImage: "film")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if appState.pendingVideoNames.count > 5 {
                        Text("…and \(appState.pendingVideoNames.count - 5) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    appState.submitVideoWarning(proceed: false)
                }
                Button("Continue without videos") {
                    appState.submitVideoWarning(proceed: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.bottom, 8)
        }
        .padding(32)
        .frame(width: 420)
    }
}

#Preview {
    let state = AppState()
    state.pendingVideoNames = ["intro.mp4", "demo.mov", "outro.mp4"]
    return VideoWarningSheet().environmentObject(state)
}

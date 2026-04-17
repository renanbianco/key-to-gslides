// ContentView.swift
// Placeholder root view — full UI is built in Task 4.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Keynote to Slides")
                .font(.largeTitle.bold())

            Text("SwiftUI shell — Task 4 will build the full UI.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Quick smoke-test: verify PythonRunner can find cli.py
            Button("Test Python bridge") {
                Task {
                    do {
                        // check_fonts on a nonexistent path should return a Python error,
                        // proving the IPC layer is reachable.
                        _ = try await PythonRunner.shared.checkFonts(pptxPath: "/tmp/does-not-exist.pptx")
                    } catch {
                        print("[PythonRunner test] \(error.localizedDescription)")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(48)
        .frame(minWidth: 640, minHeight: 480)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

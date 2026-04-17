// KeynoteToSlidesApp.swift

import SwiftUI

@main
struct KeynoteToSlidesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Remove File > New (there's no document model)
            CommandGroup(replacing: .newItem) { }
        }
    }
}

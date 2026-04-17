// DropZoneView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    var onPickFile: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor).opacity(0.6))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: isDropTargeted ? [] : [8, 5])
                )
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

            if appState.selectedFileURL == nil {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Drop a .key file or click to browse")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                    Text(appState.selectedFileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 400)
                    Text(String(format: "%.1f MB", appState.selectedFileSizeMB))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 130)
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onPickFile() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    appState.selectedFileURL = url
                    appState.phase = .idle
                }
            }
            return true
        }
    }
}

#Preview {
    DropZoneView(onPickFile: {})
        .environmentObject(AppState())
        .frame(width: 640)
}

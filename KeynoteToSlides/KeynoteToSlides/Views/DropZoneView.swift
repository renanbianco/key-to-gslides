// DropZoneView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    var onPickFile: () -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false

    private let blue     = Color(red: 0.000, green: 0.443, blue: 0.890)
    private let blueSoft = Color(red: 0.000, green: 0.443, blue: 0.890, opacity: 0.10)

    private var canRemoveFile: Bool {
        switch appState.phase {
        case .idle, .failed: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if appState.selectedFileURL != nil {
                fileChip
            } else {
                dropCard
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Empty drop card

    private var dropCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isDropTargeted
                        ? blueSoft
                        : (isHovering
                            ? Color(red: 0.949, green: 0.949, blue: 0.969)
                            : Color(red: 0.961, green: 0.961, blue: 0.969))
                )
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTargeted ? blue : Color.primary.opacity(0.12), lineWidth: 0.5)

            VStack(spacing: 8) {
                // Upload icon in a white tile
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 15))
                        .foregroundColor(
                            isDropTargeted ? blue : Color(red: 0.525, green: 0.525, blue: 0.545)
                        )
                }
                .frame(width: 36, height: 36)

                VStack(spacing: 2) {
                    Text(isDropTargeted ? "Release to add" : "Drop a Keynote file here")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.114, green: 0.114, blue: 0.122))
                        .tracking(-0.08)

                    HStack(spacing: 0) {
                        Text("or ")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(red: 0.431, green: 0.431, blue: 0.451))
                        Text("click to browse")
                            .font(.system(size: 11.5))
                            .foregroundColor(blue)
                    }
                }
            }
        }
        .frame(height: 128)
        .scaleEffect(isDropTargeted ? 1.005 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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

    // MARK: - File chip (file selected)

    private var fileChip: some View {
        HStack(spacing: 10) {
            // Doc icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(blueSoft)
                Image(systemName: "doc.fill")
                    .font(.system(size: 13))
                    .foregroundColor(blue)
            }
            .frame(width: 26, height: 26)
            .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text(appState.selectedFileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Color(red: 0.114, green: 0.114, blue: 0.122))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .tracking(-0.05)
            }

            Spacer()

            if canRemoveFile {
                Button {
                    appState.selectedFileURL = nil
                    appState.phase = .idle
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.525, green: 0.525, blue: 0.545))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

#Preview {
    DropZoneView(onPickFile: {})
        .environmentObject(AppState())
        .frame(width: 480)
}

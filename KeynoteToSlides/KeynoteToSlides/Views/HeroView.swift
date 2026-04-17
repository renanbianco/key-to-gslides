// HeroView.swift
import SwiftUI

struct HeroView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.white, Color(red: 0.918, green: 0.941, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.blue)
                Text("Keynote to Slides")
                    .font(.system(size: 23, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                Text("Convert presentations and open them directly in Google Slides.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .environment(\.colorScheme, .light)  // hero is always light
    }
}

#Preview { HeroView().frame(width: 640) }

// HeroView.swift
import SwiftUI

struct HeroView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Keynote to Google Slides")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.114, green: 0.114, blue: 0.122))
                .tracking(-0.3)
            Text("Convert and open directly in Slides.")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.431, green: 0.431, blue: 0.451))
                .tracking(-0.05)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Color.white)
    }
}

#Preview { HeroView().frame(width: 480) }

// AccountBarView.swift
import SwiftUI

struct AccountBarView: View {
    @EnvironmentObject var appState: AppState
    var onSignIn: () -> Void

    private var initials: String {
        guard let user = appState.userInfo else { return "" }
        return user.name
            .components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }

    var body: some View {
        HStack(spacing: 10) {
            if appState.isSigningIn {
                ProgressView().controlSize(.small)
                    .frame(width: 13, height: 13)
                Text("Opening your browser…")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.431, green: 0.431, blue: 0.451))
                Spacer()

            } else if let user = appState.userInfo {
                // Initials gradient circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.714, green: 0.784, blue: 0.910),
                                    Color(red: 0.478, green: 0.580, blue: 0.753),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 22, height: 22)
                .fixedSize()

                Text(user.email)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.114, green: 0.114, blue: 0.122))
                    .tracking(-0.05)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Connected badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.122, green: 0.616, blue: 0.333))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.431, green: 0.431, blue: 0.451))
                }

            } else {
                Text("Connect your Google account to continue")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.431, green: 0.431, blue: 0.451))
                    .tracking(-0.05)
                Spacer()
                Button("Sign in", action: onSignIn)
                    .buttonStyle(SmallOutlineButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
        .background(Color.white)
    }
}

// MARK: - Small outline button used for Sign in

struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color(red: 0.114, green: 0.114, blue: 0.122))
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    AccountBarView(onSignIn: {})
        .environmentObject(AppState())
        .frame(width: 480)
}

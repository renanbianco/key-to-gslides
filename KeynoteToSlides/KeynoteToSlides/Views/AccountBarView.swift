// AccountBarView.swift
import SwiftUI

struct AccountBarView: View {
    @EnvironmentObject var appState: AppState
    var onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if appState.isSigningIn {
                    ProgressView().controlSize(.small)
                    Text("Signing in… check your browser")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                } else if let user = appState.userInfo {
                    // Avatar
                    AsyncImage(url: user.pictureURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name).font(.system(size: 13, weight: .semibold))
                        Text(user.email).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Connect your Google account to get started")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appState.userInfo == nil && !appState.isSigningIn {
                    Button(action: onSignIn) {
                        Text("Sign in with Google")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.259, green: 0.522, blue: 0.957))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(.background)
        }
    }
}

#Preview {
    AccountBarView(onSignIn: {})
        .environmentObject(AppState())
        .frame(width: 640)
}

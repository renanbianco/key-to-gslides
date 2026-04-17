// GoogleAuth.swift
import Foundation
import Network
import AppKit

// MARK: - Errors

enum AuthError: LocalizedError {
    case clientSecretNotFound
    case invalidClientSecret
    case noFreePort
    case oauthError(String)
    case tokenExchangeFailed(String)
    case noRefreshToken
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .clientSecretNotFound: return "client_secret.json not found. Place it in the app bundle or credentials/ folder."
        case .invalidClientSecret: return "client_secret.json is malformed."
        case .noFreePort: return "Could not find a free local port for OAuth redirect."
        case .oauthError(let e): return "Google OAuth error: \(e)"
        case .tokenExchangeFailed(let e): return "Token exchange failed: \(e)"
        case .noRefreshToken: return "No refresh token available. Please sign in again."
        case .networkError(let e): return "Network error: \(e)"
        }
    }
}

// MARK: - GoogleAuth

actor GoogleAuth {
    static let shared = GoogleAuth()
    private init() {}

    // MARK: - Stored types

    private struct ClientSecretFile: Decodable {
        struct Installed: Decodable {
            let clientId: String
            let clientSecret: String
            let authUri: String
            let tokenUri: String
            enum CodingKeys: String, CodingKey {
                case clientId = "client_id"
                case clientSecret = "client_secret"
                case authUri = "auth_uri"
                case tokenUri = "token_uri"
            }
        }
        let installed: Installed
    }

    struct StoredToken: Codable {
        var token: String
        var refreshToken: String?
        var tokenUri: String
        var clientId: String
        var clientSecret: String
        var scopes: [String]
        var expiry: String?

        enum CodingKeys: String, CodingKey {
            case token
            case refreshToken = "refresh_token"
            case tokenUri = "token_uri"
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case scopes
            case expiry
        }

        var isExpired: Bool {
            guard let expiry, let date = ISO8601DateFormatter().date(from: expiry) else { return false }
            return Date().addingTimeInterval(60) >= date
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let tokenType: String?
        let error: String?
        let errorDescription: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case error
            case errorDescription = "error_description"
        }
    }

    private struct UserInfoResponse: Decodable {
        let email: String?
        let name: String?
        let picture: String?
    }

    // MARK: - Paths

    private var tokenFilePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".keynote_to_gslides")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token.json")
    }

    private func loadClientSecret() throws -> ClientSecretFile.Installed {
        // 1. Bundle
        if let bundleURL = Bundle.main.url(forResource: "client_secret", withExtension: "json") {
            let data = try Data(contentsOf: bundleURL)
            return try JSONDecoder().decode(ClientSecretFile.self, from: data).installed
        }
        // 2. Dev: walk up from source file
        let sourceURL = URL(fileURLWithPath: #filePath)
        let credURL = sourceURL
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // KeynoteToSlides/ (sources)
            .deletingLastPathComponent() // KeynoteToSlides/ (project)
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("credentials/client_secret.json")
        if FileManager.default.fileExists(atPath: credURL.path) {
            let data = try Data(contentsOf: credURL)
            return try JSONDecoder().decode(ClientSecretFile.self, from: data).installed
        }
        throw AuthError.clientSecretNotFound
    }

    // MARK: - Public API

    func signIn() async throws -> UserInfo {
        let secret = try loadClientSecret()
        let port = try findFreePort()
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: secret.authUri.isEmpty ? "https://accounts.google.com/o/oauth2/auth" : secret.authUri)!
        components.queryItems = [
            .init(name: "client_id", value: secret.clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile openid"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        await MainActor.run { NSWorkspace.shared.open(components.url!) }

        let code = try await waitForOAuthCode(port: port)
        let tokenResp = try await exchangeCode(code: code, clientId: secret.clientId, clientSecret: secret.clientSecret, redirectURI: redirectURI, tokenURI: secret.tokenUri.isEmpty ? "https://oauth2.googleapis.com/token" : secret.tokenUri)

        let expiryDate = tokenResp.expiresIn.map { Date().addingTimeInterval(Double($0)) }
        let expiryStr = expiryDate.map { ISO8601DateFormatter().string(from: $0) }

        let stored = StoredToken(
            token: tokenResp.accessToken,
            refreshToken: tokenResp.refreshToken,
            tokenUri: secret.tokenUri.isEmpty ? "https://oauth2.googleapis.com/token" : secret.tokenUri,
            clientId: secret.clientId,
            clientSecret: secret.clientSecret,
            scopes: ["https://www.googleapis.com/auth/drive.file",
                     "https://www.googleapis.com/auth/userinfo.email",
                     "https://www.googleapis.com/auth/userinfo.profile",
                     "openid"],
            expiry: expiryStr
        )
        try saveToken(stored)

        return try await getUserInfo(accessToken: tokenResp.accessToken)
    }

    func restoreSession() async throws -> UserInfo? {
        guard FileManager.default.fileExists(atPath: tokenFilePath.path) else { return nil }
        do {
            var stored = try loadToken()
            if stored.isExpired {
                guard let refresh = stored.refreshToken else { return nil }
                let refreshed = try await refreshAccessToken(refreshToken: refresh, clientId: stored.clientId, clientSecret: stored.clientSecret, tokenURI: stored.tokenUri)
                stored.token = refreshed.accessToken
                if let newExpiry = refreshed.expiresIn {
                    stored.expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(newExpiry)))
                }
                try saveToken(stored)
            }
            return try await getUserInfo(accessToken: stored.token)
        } catch {
            return nil
        }
    }

    func signOut() {
        try? FileManager.default.removeItem(at: tokenFilePath)
    }

    func freshAccessToken() async throws -> String {
        var stored = try loadToken()
        if stored.isExpired {
            guard let refresh = stored.refreshToken else { throw AuthError.noRefreshToken }
            let refreshed = try await refreshAccessToken(refreshToken: refresh, clientId: stored.clientId, clientSecret: stored.clientSecret, tokenURI: stored.tokenUri)
            stored.token = refreshed.accessToken
            if let newExpiry = refreshed.expiresIn {
                stored.expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(newExpiry)))
            }
            try saveToken(stored)
        }
        return stored.token
    }

    // MARK: - Private helpers

    private func findFreePort() throws -> UInt16 {
        for port: UInt16 in 8080...8099 {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(sock)
            if bound == 0 { return port }
        }
        throw AuthError.noFreePort
    }

    private func waitForOAuthCode(port: UInt16) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.renanbianco.KeynoteToSlides.oauth", qos: .userInitiated)
            guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!) else {
                continuation.resume(throwing: AuthError.noFreePort)
                return
            }

            var resumed = false

            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 10, maximumLength: 8192) { data, _, _, _ in
                    defer { listener.cancel() }
                    let html = "<html><body style='font-family:system-ui;text-align:center;padding-top:80px'><h2>✓ Signed in!</h2><p>You can close this tab and return to the app.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: response.data(using: .utf8), completion: .idempotent)

                    guard !resumed, let data,
                          let request = String(data: data, encoding: .utf8),
                          let firstLine = request.components(separatedBy: "\r\n").first else { return }

                    // firstLine: "GET /?code=XXX&... HTTP/1.1"
                    let parts = firstLine.components(separatedBy: " ")
                    guard parts.count >= 2 else { return }
                    let path = parts[1]
                    guard let urlComps = URLComponents(string: "http://localhost\(path)") else { return }

                    if let code = urlComps.queryItems?.first(where: { $0.name == "code" })?.value {
                        resumed = true
                        continuation.resume(returning: code)
                    } else if let err = urlComps.queryItems?.first(where: { $0.name == "error" })?.value {
                        resumed = true
                        continuation.resume(throwing: AuthError.oauthError(err))
                    }
                }
            }

            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state, !resumed {
                    resumed = true
                    continuation.resume(throwing: AuthError.networkError(error.localizedDescription))
                }
            }

            listener.start(queue: queue)
        }
    }

    private func exchangeCode(code: String, clientId: String, clientSecret: String, redirectURI: String, tokenURI: String) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: tokenURI)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "code=\(code)&client_id=\(clientId)&client_secret=\(clientSecret)&redirect_uri=\(redirectURI)&grant_type=authorization_code"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error {
            throw AuthError.tokenExchangeFailed(resp.errorDescription ?? err)
        }
        return resp
    }

    private func refreshAccessToken(refreshToken: String, clientId: String, clientSecret: String, tokenURI: String) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: tokenURI.isEmpty ? "https://oauth2.googleapis.com/token" : tokenURI)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "refresh_token=\(refreshToken)&client_id=\(clientId)&client_secret=\(clientSecret)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error {
            throw AuthError.tokenExchangeFailed(resp.errorDescription ?? err)
        }
        return resp
    }

    private func getUserInfo(accessToken: String) async throws -> UserInfo {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let info = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return UserInfo(
            email: info.email ?? "",
            name: info.name ?? "",
            pictureURL: info.picture.flatMap { URL(string: $0) }
        )
    }

    private func loadToken() throws -> StoredToken {
        let data = try Data(contentsOf: tokenFilePath)
        return try JSONDecoder().decode(StoredToken.self, from: data)
    }

    private func saveToken(_ token: StoredToken) throws {
        let data = try JSONEncoder().encode(token)
        try data.write(to: tokenFilePath, options: .atomic)
    }
}

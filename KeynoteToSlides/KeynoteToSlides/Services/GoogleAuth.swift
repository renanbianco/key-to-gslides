// GoogleAuth.swift
import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

// MARK: - Errors

enum AuthError: LocalizedError {
    case clientSecretNotFound
    case invalidClientSecret
    case oauthCancelled
    case oauthError(String)
    case tokenExchangeFailed(String)
    case noRefreshToken
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .clientSecretNotFound:
            return "Credentials file not found. Add client_secret.json or GoogleService-Info.plist to the bundle or credentials/ folder."
        case .invalidClientSecret:    return "Credentials file is malformed."
        case .oauthCancelled:         return "Sign-in was cancelled."
        case .oauthError(let e):      return "Google OAuth error: \(e)"
        case .tokenExchangeFailed(let e): return "Token exchange failed: \(e)"
        case .noRefreshToken:         return "No refresh token available. Please sign in again."
        case .networkError(let e):    return "Network error: \(e)"
        }
    }
}

// MARK: - Presentation context provider

private final class AuthPresentationProvider: NSObject,
                                              ASWebAuthenticationPresentationContextProviding,
                                              @unchecked Sendable {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

// MARK: - OAuthCredentials (unified across client types)

private struct OAuthCredentials {
    /// OAuth client ID.
    let clientId: String
    /// Absent for iOS/public clients — PKCE is used instead.
    let clientSecret: String?
    let authUri: String
    let tokenUri: String
    /// Full redirect URI sent to Google in the auth + token requests.
    /// • iOS client:     com.googleusercontent.apps.XXXX:/oauthredirect
    /// • Desktop client: (not supported in sandbox — use iOS client type)
    let redirectURI: String
    /// Scheme portion watched by ASWebAuthenticationSession.
    let callbackScheme: String
}

// MARK: - GoogleAuth

actor GoogleAuth {
    static let shared = GoogleAuth()
    private init() {}

    // MARK: - JSON client_secret types (Desktop / Web)

    private struct ClientSecretFile: Decodable {
        struct Credentials: Decodable {
            let clientId: String
            let clientSecret: String?
            let authUri: String
            let tokenUri: String
            enum CodingKeys: String, CodingKey {
                case clientId     = "client_id"
                case clientSecret = "client_secret"
                case authUri      = "auth_uri"
                case tokenUri     = "token_uri"
            }
        }
        let installed: Credentials?
        let web: Credentials?
        var credentials: Credentials? { installed ?? web }
    }

    // MARK: - Stored token

    struct StoredToken: Codable {
        var token: String
        var refreshToken: String?
        var tokenUri: String
        var clientId: String
        var clientSecret: String?
        var scopes: [String]
        var expiry: String?

        enum CodingKeys: String, CodingKey {
            case token
            case refreshToken = "refresh_token"
            case tokenUri     = "token_uri"
            case clientId     = "client_id"
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
            case accessToken      = "access_token"
            case refreshToken     = "refresh_token"
            case expiresIn        = "expires_in"
            case tokenType        = "token_type"
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
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("KeynoteToSlides")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token.json")
    }

    // MARK: - Credential loading (JSON + plist)

    /// Loads OAuth credentials from either:
    ///   • `GoogleService-Info.plist`  (iOS client — preferred, supports custom scheme)
    ///   • `client_secret.json`        (Desktop/Web client — legacy, not usable in sandbox)
    ///
    /// Search order: bundle resource first, then dev `credentials/` folder next to repo root.
    private func loadCredentials() throws -> OAuthCredentials {
        // ── Plist (iOS client) ────────────────────────────────────────────────
        if let cred = try? loadPlist(from: bundleURL(resource: "GoogleService-Info", ext: "plist")
                                        ?? devURL(filename: "GoogleService-Info.plist")) {
            return cred
        }
        // ── JSON (Desktop / Web client) ───────────────────────────────────────
        if let cred = try? loadJSON(from: bundleURL(resource: "client_secret", ext: "json")
                                        ?? devURL(filename: "client_secret.json")) {
            return cred
        }
        throw AuthError.clientSecretNotFound
    }

    /// Parses a `GoogleService-Info.plist` downloaded from Google Cloud Console
    /// (iOS OAuth 2.0 client type).
    private func loadPlist(from url: URL?) throws -> OAuthCredentials {
        guard let url else { throw AuthError.clientSecretNotFound }
        let data = try Data(contentsOf: url)
        var fmt = PropertyListSerialization.PropertyListFormat.xml
        guard let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: &fmt) as? [String: Any]
        else { throw AuthError.invalidClientSecret }

        // Required keys in GoogleService-Info.plist
        guard let clientId         = dict["CLIENT_ID"] as? String,
              let reversedClientId = dict["REVERSED_CLIENT_ID"] as? String,
              !clientId.isEmpty, !reversedClientId.isEmpty
        else { throw AuthError.invalidClientSecret }

        // Redirect URI for iOS clients:  REVERSED_CLIENT_ID:/oauthredirect
        // ASWebAuthenticationSession watches for scheme = REVERSED_CLIENT_ID
        return OAuthCredentials(
            clientId:       clientId,
            clientSecret:   nil,   // iOS clients are public; PKCE used instead
            authUri:        "https://accounts.google.com/o/oauth2/auth",
            tokenUri:       "https://oauth2.googleapis.com/token",
            redirectURI:    "\(reversedClientId):/oauthredirect",
            callbackScheme: reversedClientId
        )
    }

    /// Parses a `client_secret.json` (Desktop or Web application client type).
    private func loadJSON(from url: URL?) throws -> OAuthCredentials {
        guard let url else { throw AuthError.clientSecretNotFound }
        let data = try Data(contentsOf: url)
        guard let cred = try JSONDecoder().decode(ClientSecretFile.self, from: data).credentials else {
            throw AuthError.invalidClientSecret
        }
        let effectiveSecret = cred.clientSecret.flatMap { $0.isEmpty ? nil : $0 }
        // Desktop/Web JSON clients cannot be used with custom-scheme redirect in sandbox.
        // Kept for dev builds that run without sandbox (e.g. from Xcode with sandbox OFF).
        let scheme = "com.renanbianco.keynotetoslides"
        return OAuthCredentials(
            clientId:       cred.clientId,
            clientSecret:   effectiveSecret,
            authUri:        cred.authUri.isEmpty  ? "https://accounts.google.com/o/oauth2/auth" : cred.authUri,
            tokenUri:       cred.tokenUri.isEmpty ? "https://oauth2.googleapis.com/token"       : cred.tokenUri,
            redirectURI:    "\(scheme):/oauthredirect",
            callbackScheme: scheme
        )
    }

    private func bundleURL(resource: String, ext: String) -> URL? {
        Bundle.main.url(forResource: resource, withExtension: ext)
    }

    private func devURL(filename: String) -> URL? {
        // Walk up from this source file to the repo root, then into credentials/
        let src = URL(fileURLWithPath: #filePath)
        let url = src
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // KeynoteToSlides/ (sources)
            .deletingLastPathComponent() // KeynoteToSlides/ (project)
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("credentials/\(filename)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - PKCE (RFC 7636 S256)

    private func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (verifier, challenge)
    }

    // MARK: - Public API

    func signIn() async throws -> UserInfo {
        let cred = try loadCredentials()
        let (pkceVerifier, pkceChallenge) = generatePKCE()

        var comps = URLComponents(string: cred.authUri)!
        comps.queryItems = [
            .init(name: "client_id",             value: cred.clientId),
            .init(name: "redirect_uri",           value: cred.redirectURI),
            .init(name: "response_type",          value: "code"),
            .init(name: "scope",                  value: "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile openid"),
            .init(name: "access_type",            value: "offline"),
            .init(name: "prompt",                 value: "consent"),
            .init(name: "code_challenge",         value: pkceChallenge),
            .init(name: "code_challenge_method",  value: "S256"),
        ]
        guard let authURL = comps.url else {
            throw AuthError.oauthError("Failed to build OAuth URL")
        }

        let callbackURL = try await webAuthSession(url: authURL, callbackScheme: cred.callbackScheme)

        guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.oauthError("Invalid callback URL: \(callbackURL)")
        }
        if let err = callbackComps.queryItems?.first(where: { $0.name == "error" })?.value {
            throw AuthError.oauthError(err)
        }
        guard let code = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.oauthError("No authorization code in callback URL")
        }

        let tokenResp = try await exchangeCode(
            code:         code,
            clientId:     cred.clientId,
            clientSecret: cred.clientSecret,
            codeVerifier: pkceVerifier,
            redirectURI:  cred.redirectURI,
            tokenURI:     cred.tokenUri
        )

        let expiryStr = tokenResp.expiresIn.map {
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double($0)))
        }
        let stored = StoredToken(
            token:         tokenResp.accessToken,
            refreshToken:  tokenResp.refreshToken,
            tokenUri:      cred.tokenUri,
            clientId:      cred.clientId,
            clientSecret:  cred.clientSecret,
            scopes: [
                "https://www.googleapis.com/auth/drive.file",
                "https://www.googleapis.com/auth/userinfo.email",
                "https://www.googleapis.com/auth/userinfo.profile",
                "openid",
            ],
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
                let refreshed = try await refreshAccessToken(
                    refreshToken: refresh,
                    clientId:     stored.clientId,
                    clientSecret: stored.clientSecret,
                    tokenURI:     stored.tokenUri
                )
                stored.token = refreshed.accessToken
                if let newExpiry = refreshed.expiresIn {
                    stored.expiry = ISO8601DateFormatter().string(
                        from: Date().addingTimeInterval(Double(newExpiry))
                    )
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
            let refreshed = try await refreshAccessToken(
                refreshToken: refresh,
                clientId:     stored.clientId,
                clientSecret: stored.clientSecret,
                tokenURI:     stored.tokenUri
            )
            stored.token = refreshed.accessToken
            if let newExpiry = refreshed.expiresIn {
                stored.expiry = ISO8601DateFormatter().string(
                    from: Date().addingTimeInterval(Double(newExpiry))
                )
            }
            try saveToken(stored)
        }
        return stored.token
    }

    // MARK: - ASWebAuthenticationSession

    private func webAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        let provider = AuthPresentationProvider()
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    if let error {
                        let nsErr = error as NSError
                        if nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: AuthError.oauthCancelled)
                        } else {
                            continuation.resume(throwing: AuthError.oauthError(error.localizedDescription))
                        }
                    } else if let url = callbackURL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AuthError.oauthError("No callback URL received"))
                    }
                }
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
        }
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(
        code: String,
        clientId: String,
        clientSecret: String?,
        codeVerifier: String?,
        redirectURI: String,
        tokenURI: String
    ) async throws -> TokenResponse {
        // Build body using URLComponents for correct percent-encoding.
        var bodyComps = URLComponents()
        var items: [URLQueryItem] = [
            .init(name: "code",         value: code),
            .init(name: "client_id",    value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "grant_type",   value: "authorization_code"),
        ]
        if let s = clientSecret  { items.append(.init(name: "client_secret", value: s)) }
        if let v = codeVerifier  { items.append(.init(name: "code_verifier", value: v)) }
        bodyComps.queryItems = items

        var req = URLRequest(url: URL(string: tokenURI)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error { throw AuthError.tokenExchangeFailed(resp.errorDescription ?? err) }
        return resp
    }

    private func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String?,
        tokenURI: String
    ) async throws -> TokenResponse {
        let uri = tokenURI.isEmpty ? "https://oauth2.googleapis.com/token" : tokenURI
        var bodyComps = URLComponents()
        var items: [URLQueryItem] = [
            .init(name: "refresh_token", value: refreshToken),
            .init(name: "client_id",     value: clientId),
            .init(name: "grant_type",    value: "refresh_token"),
        ]
        if let s = clientSecret { items.append(.init(name: "client_secret", value: s)) }
        bodyComps.queryItems = items

        var req = URLRequest(url: URL(string: uri)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let err = resp.error { throw AuthError.tokenExchangeFailed(resp.errorDescription ?? err) }
        return resp
    }

    // MARK: - User info

    private func getUserInfo(accessToken: String) async throws -> UserInfo {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let info = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return UserInfo(
            email:      info.email ?? "",
            name:       info.name  ?? "",
            pictureURL: info.picture.flatMap { URL(string: $0) }
        )
    }

    // MARK: - Token persistence

    private func loadToken() throws -> StoredToken {
        let data = try Data(contentsOf: tokenFilePath)
        return try JSONDecoder().decode(StoredToken.self, from: data)
    }

    private func saveToken(_ token: StoredToken) throws {
        let data = try JSONEncoder().encode(token)
        try data.write(to: tokenFilePath, options: .atomic)
    }
}

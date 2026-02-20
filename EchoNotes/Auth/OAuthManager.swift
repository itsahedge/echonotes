import Foundation
import AppKit
import CryptoKit
import os

/// Manages OpenAI OAuth 2.1 + PKCE authentication flow.
/// Uses the same client ID and endpoints as OpenAI Codex CLI.
@MainActor
final class OAuthManager: ObservableObject {
    private let logger = Logger(subsystem: "com.echonotes", category: "OAuth")

    // OpenAI OAuth constants (same as Codex CLI)
    static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = "https://auth.openai.com"
    static let authorizeURL = "\(issuer)/oauth/authorize"
    static let tokenURL = "\(issuer)/oauth/token"
    static let scopes = "openid profile email offline_access"

    // Local callback server port
    private static let callbackPort: UInt16 = 18923

    @Published var isAuthenticating = false
    @Published var isAuthenticated = false
    @Published var error: String?
    @Published var userEmail: String?

    private var callbackServer: OAuthCallbackServer?
    private var pkce: PKCECodes?
    private var state: String?

    /// Stored tokens
    struct OAuthTokens: Codable {
        var accessToken: String
        var refreshToken: String
        var idToken: String
        var apiKey: String?
        var email: String?
        var expiresAt: Date?

        var isExpired: Bool {
            guard let exp = expiresAt else { return false }
            return Date() > exp
        }
    }

    private static let tokensKey = "oauthTokens"

    /// Load stored tokens
    var storedTokens: OAuthTokens? {
        guard let data = UserDefaults.standard.data(forKey: Self.tokensKey),
              let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data) else {
            return nil
        }
        return tokens
    }

    init() {
        if let tokens = storedTokens {
            isAuthenticated = true
            userEmail = tokens.email
        }
    }

    // MARK: - PKCE

    struct PKCECodes {
        let codeVerifier: String
        let codeChallenge: String
    }

    nonisolated static func generatePKCE() -> PKCECodes {
        // Generate 32 random bytes → base64url
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()

        // SHA256 hash of verifier → base64url
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncoded()

        return PKCECodes(codeVerifier: verifier, codeChallenge: challenge)
    }

    nonisolated static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    // MARK: - Login Flow

    /// Start the OAuth login flow.
    func login() {
        isAuthenticating = true
        error = nil

        let pkce = Self.generatePKCE()
        let state = Self.generateState()
        self.pkce = pkce
        self.state = state

        // Start local callback server
        let server = OAuthCallbackServer(port: Self.callbackPort) { [weak self] code, returnedState in
            Task { @MainActor in
                guard let self else { return }
                guard returnedState == self.state else {
                    self.error = "OAuth state mismatch — possible CSRF attack"
                    self.isAuthenticating = false
                    return
                }
                await self.exchangeCodeForTokens(code: code)
            }
        }

        do {
            try server.start()
            self.callbackServer = server
        } catch {
            self.error = "Failed to start callback server: \(error.localizedDescription)"
            self.isAuthenticating = false
            return
        }

        // Build authorization URL
        let redirectURI = "http://localhost:\(Self.callbackPort)/callback"
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
        ]

        guard let authURL = components.url else {
            self.error = "Failed to build authorization URL"
            self.isAuthenticating = false
            return
        }

        logger.info("Opening browser for OAuth: \(authURL.absoluteString)")
        NSWorkspace.shared.open(authURL)
    }

    // MARK: - Token Exchange

    /// Exchange the authorization code for tokens.
    private func exchangeCodeForTokens(code: String) async {
        guard let pkce else {
            error = "PKCE not initialized"
            isAuthenticating = false
            return
        }

        let redirectURI = "http://localhost:\(Self.callbackPort)/callback"

        // Step 1: Exchange code for id_token + access_token + refresh_token
        let tokenBody = [
            "grant_type=authorization_code",
            "code=\(code.urlEncoded)",
            "redirect_uri=\(redirectURI.urlEncoded)",
            "client_id=\(Self.clientId.urlEncoded)",
            "code_verifier=\(pkce.codeVerifier.urlEncoded)",
        ].joined(separator: "&")

        do {
            var request = URLRequest(url: URL(string: Self.tokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = tokenBody.data(using: .utf8)
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                throw OAuthError.tokenExchangeFailed("Token exchange failed: \(body)")
            }

            struct TokenResponse: Decodable {
                let id_token: String
                let access_token: String
                let refresh_token: String
            }
            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)

            // Step 2: Exchange id_token for an API key
            let apiKey = try await exchangeForAPIKey(idToken: tokens.id_token)

            // Extract email from id_token JWT
            let email = Self.extractEmailFromJWT(tokens.id_token)

            // Store everything
            let stored = OAuthTokens(
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token,
                idToken: tokens.id_token,
                apiKey: apiKey,
                email: email,
                expiresAt: Date().addingTimeInterval(3600 * 8) // ~8 hours
            )
            saveTokens(stored)

            isAuthenticated = true
            userEmail = email
            logger.info("OAuth login successful for \(email ?? "unknown")")
        } catch {
            self.error = error.localizedDescription
            logger.error("OAuth error: \(error.localizedDescription)")
        }

        isAuthenticating = false
        callbackServer?.stop()
        callbackServer = nil
    }

    /// Exchange id_token for an OpenAI API key via token exchange grant.
    private func exchangeForAPIKey(idToken: String) async throws -> String {
        let body = [
            "grant_type=\("urn:ietf:params:oauth:grant-type:token-exchange".urlEncoded)",
            "client_id=\(Self.clientId.urlEncoded)",
            "requested_token=\("openai-api-key".urlEncoded)",
            "subject_token=\(idToken.urlEncoded)",
            "subject_token_type=\("urn:ietf:params:oauth:token-type:id_token".urlEncoded)",
        ].joined(separator: "&")

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.apiKeyExchangeFailed("API key exchange failed: \(responseBody)")
        }

        struct ExchangeResponse: Decodable {
            let access_token: String
        }
        let exchanged = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        return exchanged.access_token
    }

    // MARK: - Token Refresh

    /// Refresh tokens using the stored refresh token.
    func refreshTokensIfNeeded() async {
        guard let tokens = storedTokens, tokens.isExpired else { return }

        let body = [
            "grant_type=refresh_token",
            "client_id=\(Self.clientId.urlEncoded)",
            "refresh_token=\(tokens.refreshToken.urlEncoded)",
        ].joined(separator: "&")

        do {
            var request = URLRequest(url: URL(string: Self.tokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Refresh failed — user needs to re-login
                logout()
                return
            }

            struct RefreshResponse: Decodable {
                let id_token: String
                let access_token: String
                let refresh_token: String
            }
            let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)

            // Get new API key
            let apiKey = try await exchangeForAPIKey(idToken: refreshed.id_token)
            let email = Self.extractEmailFromJWT(refreshed.id_token)

            let updated = OAuthTokens(
                accessToken: refreshed.access_token,
                refreshToken: refreshed.refresh_token,
                idToken: refreshed.id_token,
                apiKey: apiKey,
                email: email,
                expiresAt: Date().addingTimeInterval(3600 * 8)
            )
            saveTokens(updated)
            userEmail = email
            logger.info("Token refresh successful")
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            logout()
        }
    }

    // MARK: - Logout

    func logout() {
        UserDefaults.standard.removeObject(forKey: Self.tokensKey)
        isAuthenticated = false
        userEmail = nil
        error = nil
    }

    // MARK: - Storage

    private func saveTokens(_ tokens: OAuthTokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: Self.tokensKey)
        }
    }

    // MARK: - JWT Parsing

    nonisolated static func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        // Add padding if needed
        while payload.count % 4 != 0 { payload += "=" }
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case tokenExchangeFailed(String)
    case apiKeyExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed(let msg): return msg
        case .apiKeyExchangeFailed(let msg): return msg
        }
    }
}

// MARK: - Extensions

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

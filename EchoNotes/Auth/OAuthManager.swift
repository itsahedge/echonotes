import Foundation
import SwiftUI
import CryptoKit
import Network

/// Manages OpenAI OAuth 2.0 PKCE authentication flow.
///
/// **Important:** Replace `clientID` with a real OAuth client ID after registering
/// at https://platform.openai.com. The current value is a placeholder.
@MainActor
final class OAuthManager: ObservableObject {
    // TODO: Replace with real client ID after registering the OAuth app at https://platform.openai.com
    private static let clientID = "REPLACE_WITH_OPENAI_CLIENT_ID"

    private static let authorizeURL = "https://auth.openai.com/authorize"
    private static let tokenURL = "https://auth.openai.com/token"
    private static let scopes = "openai.organization.read openai.models.read"

    private static let keychainAccessToken = "openai_access_token"
    private static let keychainRefreshToken = "openai_refresh_token"
    private static let keychainExpiresAt = "openai_expires_at"

    @Published var isSignedIn = false

    init() {
        // Check if we have a stored token
        isSignedIn = (try? KeychainStore.load(key: Self.keychainAccessToken)) != nil
    }

    /// Full sign-in flow: starts server, opens browser, waits for callback, exchanges code.
    func performSignIn() async throws {
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        // Start local callback server
        let server = CallbackServer()
        let port = try await server.start()

        let redirectURI = "http://127.0.0.1:\(port)/callback"

        // Build authorization URL
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        // Open browser
        NSWorkspace.shared.open(components.url!)

        // Wait for callback
        let code = try await server.waitForCode(expectedState: state)
        server.stop()

        // Exchange code for tokens
        try await exchangeCode(code, codeVerifier: codeVerifier, redirectURI: redirectURI)
        isSignedIn = true
    }

    /// Clear all tokens and sign out.
    func signOut() {
        try? KeychainStore.delete(key: Self.keychainAccessToken)
        try? KeychainStore.delete(key: Self.keychainRefreshToken)
        try? KeychainStore.delete(key: Self.keychainExpiresAt)
        isSignedIn = false
    }

    /// Get a valid access token, refreshing if expired.
    func getAccessToken() async throws -> String {
        guard let tokenData = try KeychainStore.load(key: Self.keychainAccessToken),
              let token = String(data: tokenData, encoding: .utf8) else {
            throw OAuthError.notSignedIn
        }

        // Check expiration
        if let expiresData = try KeychainStore.load(key: Self.keychainExpiresAt),
           let expiresString = String(data: expiresData, encoding: .utf8),
           let expiresAt = Double(expiresString) {
            if Date().timeIntervalSince1970 >= expiresAt - 60 {
                // Token expired or about to expire — refresh
                return try await refreshAccessToken()
            }
        }

        return token
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, codeVerifier: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)",
            "client_id=\(Self.clientID)",
            "code_verifier=\(codeVerifier)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed
        }

        try saveTokenResponse(data)
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshData = try KeychainStore.load(key: Self.keychainRefreshToken),
              let refreshToken = String(data: refreshData, encoding: .utf8) else {
            throw OAuthError.notSignedIn
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(Self.clientID)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Refresh failed — sign out
            signOut()
            throw OAuthError.tokenRefreshFailed
        }

        try saveTokenResponse(data)

        guard let tokenData = try KeychainStore.load(key: Self.keychainAccessToken),
              let token = String(data: tokenData, encoding: .utf8) else {
            throw OAuthError.tokenExchangeFailed
        }
        return token
    }

    private func saveTokenResponse(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed
        }

        try KeychainStore.save(key: Self.keychainAccessToken, data: Data(accessToken.utf8))

        if let refreshToken = json["refresh_token"] as? String {
            try KeychainStore.save(key: Self.keychainRefreshToken, data: Data(refreshToken.utf8))
        }

        if let expiresIn = json["expires_in"] as? Double {
            let expiresAt = Date().timeIntervalSince1970 + expiresIn
            try KeychainStore.save(key: Self.keychainExpiresAt, data: Data(String(expiresAt).utf8))
        }
    }

    // MARK: - PKCE Helpers

    private static func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        let length = Int.random(in: 43...128)
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case notSignedIn
    case tokenExchangeFailed
    case tokenRefreshFailed
    case callbackFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to OpenAI."
        case .tokenExchangeFailed: return "Failed to exchange authorization code for tokens."
        case .tokenRefreshFailed: return "Failed to refresh access token."
        case .callbackFailed: return "OAuth callback failed."
        }
    }
}

// MARK: - Local Callback Server

/// Lightweight HTTP server using NWListener to catch the OAuth callback.
private final class CallbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        cont.resume(returning: port.rawValue)
                    }
                case .failed(let error):
                    cont.resume(throwing: error)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func waitForCode(expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the GET request for code and state
            let code = self.extractParam(from: request, name: "code")
            _ = self.extractParam(from: request, name: "state")

            // Send response
            let html = "<html><body><h2>Sign-in complete!</h2><p>You can close this tab and return to EchoNotes.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            // Deliver the code
            self.lock.lock()
            let cont = self.continuation
            self.continuation = nil
            self.lock.unlock()

            if let code {
                cont?.resume(returning: code)
            } else {
                cont?.resume(throwing: OAuthError.callbackFailed)
            }
        }
    }

    private func extractParam(from request: String, name: String) -> String? {
        // Find the GET line, extract query string
        guard let firstLine = request.split(separator: "\r\n").first,
              let urlPart = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(urlPart)) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }
}

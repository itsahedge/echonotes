import Testing
import Foundation
@testable import EchoNotes

@Suite("OAuthManager")
struct OAuthManagerTests {

    // MARK: - PKCE

    @Test("PKCE generates valid code verifier")
    func pkceVerifier() {
        let pkce = OAuthManager.generatePKCE()
        #expect(!pkce.codeVerifier.isEmpty)
        #expect(pkce.codeVerifier.count >= 32)
        // Base64URL should not contain +, /, or =
        #expect(!pkce.codeVerifier.contains("+"))
        #expect(!pkce.codeVerifier.contains("/"))
        #expect(!pkce.codeVerifier.contains("="))
    }

    @Test("PKCE generates valid code challenge")
    func pkceChallenge() {
        let pkce = OAuthManager.generatePKCE()
        #expect(!pkce.codeChallenge.isEmpty)
        // Challenge should be different from verifier (it's a hash)
        #expect(pkce.codeChallenge != pkce.codeVerifier)
        // Base64URL format
        #expect(!pkce.codeChallenge.contains("+"))
        #expect(!pkce.codeChallenge.contains("/"))
        #expect(!pkce.codeChallenge.contains("="))
    }

    @Test("PKCE generates unique pairs each time")
    func pkceUnique() {
        let a = OAuthManager.generatePKCE()
        let b = OAuthManager.generatePKCE()
        #expect(a.codeVerifier != b.codeVerifier)
        #expect(a.codeChallenge != b.codeChallenge)
    }

    // MARK: - State Generation

    @Test("State generation produces unique values")
    func stateUnique() {
        let a = OAuthManager.generateState()
        let b = OAuthManager.generateState()
        #expect(a != b)
        #expect(!a.isEmpty)
    }

    @Test("State is base64url encoded")
    func stateFormat() {
        let state = OAuthManager.generateState()
        #expect(!state.contains("+"))
        #expect(!state.contains("/"))
        #expect(!state.contains("="))
    }

    // MARK: - JWT Parsing

    @Test("Extract email from valid JWT")
    func extractEmailFromJWT() {
        // Create a fake JWT with email in payload
        let header = Data("{}".utf8).base64URLEncoded()
        let payload = Data(#"{"email":"test@example.com","sub":"user123"}"#.utf8).base64URLEncoded()
        let signature = "fakesig"
        let jwt = "\(header).\(payload).\(signature)"

        let email = OAuthManager.extractEmailFromJWT(jwt)
        #expect(email == "test@example.com")
    }

    @Test("Extract email returns nil for JWT without email")
    func extractEmailNoEmail() {
        let header = Data("{}".utf8).base64URLEncoded()
        let payload = Data(#"{"sub":"user123"}"#.utf8).base64URLEncoded()
        let jwt = "\(header).\(payload).sig"

        let email = OAuthManager.extractEmailFromJWT(jwt)
        #expect(email == nil)
    }

    @Test("Extract email returns nil for invalid JWT")
    func extractEmailInvalidJWT() {
        #expect(OAuthManager.extractEmailFromJWT("not-a-jwt") == nil)
        #expect(OAuthManager.extractEmailFromJWT("") == nil)
        #expect(OAuthManager.extractEmailFromJWT("a.b") == nil)
    }

    // MARK: - Token Storage

    @Test("OAuthTokens round-trip JSON encoding")
    func tokensRoundTrip() throws {
        let tokens = OAuthManager.OAuthTokens(
            accessToken: "acc_123",
            refreshToken: "ref_456",
            idToken: "id_789",
            apiKey: "sk-test",
            email: "user@example.com",
            expiresAt: Date(timeIntervalSince1970: 1700000000)
        )
        let encoded = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode(OAuthManager.OAuthTokens.self, from: encoded)
        #expect(decoded.accessToken == "acc_123")
        #expect(decoded.refreshToken == "ref_456")
        #expect(decoded.apiKey == "sk-test")
        #expect(decoded.email == "user@example.com")
    }

    @Test("Token expiry check works")
    func tokenExpiry() {
        let expired = OAuthManager.OAuthTokens(
            accessToken: "a", refreshToken: "r", idToken: "i",
            expiresAt: Date().addingTimeInterval(-3600)
        )
        #expect(expired.isExpired)

        let valid = OAuthManager.OAuthTokens(
            accessToken: "a", refreshToken: "r", idToken: "i",
            expiresAt: Date().addingTimeInterval(3600)
        )
        #expect(!valid.isExpired)
    }

    @Test("Token without expiry is not expired")
    func tokenNoExpiry() {
        let tokens = OAuthManager.OAuthTokens(
            accessToken: "a", refreshToken: "r", idToken: "i",
            expiresAt: nil
        )
        #expect(!tokens.isExpired)
    }

    // MARK: - Constants

    @Test("OAuth constants match Codex CLI")
    func constants() {
        #expect(OAuthManager.clientId == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(OAuthManager.issuer == "https://auth.openai.com")
        #expect(OAuthManager.tokenURL == "https://auth.openai.com/oauth/token")
    }

    // MARK: - URL Encoding

    @Test("URL encoding handles special characters")
    func urlEncoding() {
        let input = "hello world+test/path=value"
        let encoded = input.urlEncoded
        #expect(!encoded.contains(" "))
    }

    // MARK: - Base64URL

    @Test("Base64URL encoding removes padding and substitutes chars")
    func base64URL() {
        let data = Data([0xFF, 0xFE, 0xFD, 0xFC]) // Will produce + and / in regular base64
        let encoded = data.base64URLEncoded()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }
}

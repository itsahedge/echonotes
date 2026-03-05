import SwiftUI

struct AIProvidersSettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    @State private var anthropicApiKeyInput: String = ""
    @State private var googleApiKeyInput: String = ""
    
    init(tm: TranscriptionManager) {
        self.tm = tm
        _anthropicApiKeyInput = State(initialValue: tm.anthropicAPIKey)
        _googleApiKeyInput = State(initialValue: tm.googleAPIKey)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                providerSection(provider: .openai, title: "OpenAI", icon: "brain.head.profile") {
                    openaiOAuthSection
                    openaiApiKeySection
                }
                
                providerSection(provider: .anthropic, title: "Anthropic", icon: "antenna.radiowaves.left.right") {
                    anthropicApiKeySection
                }
                
                providerSection(provider: .google, title: "Google Gemini", icon: "star.circle") {
                    googleApiKeySection
                }
                
                providerSection(provider: .ollama, title: "Ollama (Local)", icon: "cube.box") {
                    ollamaSection
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Provider Section Helper
    
    @ViewBuilder
    private func providerSection<Content: View>(
        provider: AIProvider,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text(title)
                    .font(.headline)
                Spacer()
                if isSelected(provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            
            content()
        }
        .padding(16)
                .background(isSelected(provider) ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func isSelected(_ provider: AIProvider) -> Bool {
        tm.selectedProvider == provider
    }
    
    // MARK: - OpenAI Sections
    
    private var openaiOAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sign in with ChatGPT", systemImage: "person.circle")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            Text("Use your ChatGPT Plus/Pro subscription for API access")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            if tm.oauthManager.isAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authenticated")
                            .font(.callout.bold())
                        if let email = tm.oauthManager.userEmail {
                            Text(email)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: { tm.oauthManager.logout() }) {
                        Text("Sign Out")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button(action: { tm.oauthManager.login() }) {
                    HStack(spacing: 6) {
                        if tm.oauthManager.isAuthenticating {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Authenticating...")
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Sign in with ChatGPT")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tm.oauthManager.isAuthenticating)
                
                if let error = tm.oauthManager.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    private var openaiApiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if tm.isAIConfigured {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            HStack(spacing: 8) {
                SecureField("sk-...", text: $tm.openaiAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                
                if !tm.openaiAPIKey.isEmpty {
                    Button(action: { tm.openaiAPIKey = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Anthropic Sections
    
    private var anthropicApiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !tm.anthropicAPIKey.isEmpty {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            HStack(spacing: 8) {
                SecureField("sk-ant-...", text: $anthropicApiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: anthropicApiKeyInput) { _, newValue in
                        tm.anthropicAPIKey = newValue
                    }
                
                if !tm.anthropicAPIKey.isEmpty {
                    Button(action: {
                        tm.anthropicAPIKey = ""
                        anthropicApiKeyInput = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Link("Get API key from Anthropic", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
    
    // MARK: - Google Sections
    
    private var googleApiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !tm.googleAPIKey.isEmpty {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            HStack(spacing: 8) {
                SecureField("AIza...", text: $googleApiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: googleApiKeyInput) { _, newValue in
                        tm.googleAPIKey = newValue
                    }
                
                if !tm.googleAPIKey.isEmpty {
                    Button(action: {
                        tm.googleAPIKey = ""
                        googleApiKeyInput = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Link("Get API key from Google Cloud", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
    
    // MARK: - Ollama Section
    
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("No API key required — Ollama runs locally")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Text("Make sure Ollama is running on localhost:11434")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
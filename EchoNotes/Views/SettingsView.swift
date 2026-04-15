import SwiftUI

/// Settings page for app configuration (AI provider, model, OAuth, etc).
struct SettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    var onBack: (() -> Void)? = nil

    @State private var apiKeyInput: String = ""
    @State private var showKey = false
    @State private var saved = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 12) {
            if let onBack {
                // Header (only shown when used standalone)
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tm.selectedProvider == .openai {
                        oauthSection
                    } else if tm.selectedProvider == .anthropic {
                        anthropicSubscriptionSection
                    }
                    aiProviderSection
                }
            }
        }
        .onAppear {
            apiKeyInput = currentAPIKey
        }
        .onChange(of: tm.selectedProvider) { _, _ in
            apiKeyInput = currentAPIKey
        }
    }

    // MARK: - OAuth Section

    private var oauthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sign In with Account", systemImage: "person.crop.circle")
                .font(.subheadline.bold())

            Text("Sign in with your existing ChatGPT subscription instead of an API key. Your Plus/Pro plan includes API access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if tm.oauthManager.isAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with ChatGPT")
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
                            ProgressView().controlSize(.mini)
                            Text("Waiting for browser...")
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Sign in with ChatGPT")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
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
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Per-Provider API Key Helpers

    private var currentAPIKey: String {
        switch tm.selectedProvider {
        case .openai: return tm.openaiAPIKey
        case .anthropic: return tm.anthropicAPIKey
        case .google: return tm.googleAPIKey
        default: return ""
        }
    }

    private func saveAPIKey(_ key: String) {
        switch tm.selectedProvider {
        case .openai: tm.openaiAPIKey = key
        case .anthropic: tm.anthropicAPIKey = key
        case .google: tm.googleAPIKey = key
        default: break
        }
    }

    // MARK: - Anthropic Subscription Section

    @State private var anthropicTokenInput: String = ""

    private var anthropicSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude Subscription Auth", systemImage: "person.crop.circle")
                .font(.subheadline.bold())

            Text("Use your Claude Max/Pro subscription instead of an API key. Requires the Claude Code CLI.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if tm.isAnthropicSubscriptionAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Using your Claude subscription for Anthropic API access")
                        .font(.callout.bold())
                    Spacer()
                    Button(action: { tm.anthropicSetupToken = "" }) {
                        Text("Sign Out")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Run this command in Terminal:")
                        .font(.callout)
                    HStack(spacing: 6) {
                        Text("`claude setup-token`")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("claude setup-token", forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy command")
                    }
                    Text("2. Paste the token below:")
                        .font(.callout)
                    SecureField("Paste setup token...", text: $anthropicTokenInput)
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        let trimmed = anthropicTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            tm.anthropicSetupToken = trimmed
                            anthropicTokenInput = ""
                        }
                    }) {
                        Text("Save Token")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(anthropicTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("Anthropic may restrict subscription usage outside Claude Code. Use at your own risk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - AI Provider Section

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Summarization", systemImage: "sparkles")
                .font(.subheadline.bold())

            if tm.oauthManager.isAuthenticated && tm.selectedProvider == .openai {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text("Using your ChatGPT account for OpenAI API access")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if tm.isAnthropicSubscriptionAuthenticated && tm.selectedProvider == .anthropic {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text("Using your Claude subscription for Anthropic API access")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose an AI provider for meeting summaries. Your API key is stored locally and never sent anywhere except the provider's API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Provider picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)

                Picker("", selection: $tm.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: tm.selectedProvider) { _, newValue in
                    tm.selectedAIModel = newValue.defaultModel
                    if newValue.requiresAPIKey && apiKeyInput.isEmpty {
                        apiKeyInput = ""
                    }
                }
            }

            // Model picker (not shown for custom — it's in the endpoint config below)
            if tm.selectedProvider != .custom {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)

                    Picker("", selection: $tm.selectedAIModel) {
                        ForEach(tm.selectedProvider.modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // API Key (if required and not using OAuth or subscription auth)
            if tm.selectedProvider.requiresAPIKey
                && !(tm.oauthManager.isAuthenticated && tm.selectedProvider == .openai)
                && !(tm.isAnthropicSubscriptionAuthenticated && tm.selectedProvider == .anthropic) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField(tm.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            } else {
                                SecureField(tm.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            saveAPIKey(apiKeyInput)
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }) {
                            Text(saved ? "Saved" : "Save")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput == currentAPIKey)

                        if !currentAPIKey.isEmpty {
                            Button(action: {
                                saveAPIKey("")
                                apiKeyInput = ""
                            }) {
                                Text("Remove Key")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }

                        Spacer()

                        if tm.isAIConfigured {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } else if tm.selectedProvider == .custom {
                customEndpointSection
            } else if !tm.selectedProvider.requiresAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No API key needed — make sure Ollama is running locally")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Custom Endpoint

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect to any OpenAI-compatible API (llama.cpp, vLLM, LM Studio, etc).")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Endpoint")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                TextField("URL", text: $tm.customEndpoint, prompt: Text("http://localhost:8080/v1/chat/completions"))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                TextField("Model name", text: $tm.customModel, prompt: Text("e.g. qwen3.5-35b-a3b"))
                    .textFieldStyle(.roundedBorder)
                Text("The model name sent in the request body.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                SecureField("API key", text: $tm.customAPIKey, prompt: Text("Leave empty if not required"))
                    .textFieldStyle(.roundedBorder)
                Text("Only needed if your server requires authentication.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button(action: { testCustomConnection() }) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(tm.customEndpoint.isEmpty || isTesting)
            }

            if let result = connectionTestResult {
                HStack(spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    Text(result.message)
                        .font(.callout)
                        .foregroundStyle(result.success ? .primary : Color.red)
                }
            }
        }
    }

    // MARK: - Test Connection

    private func testCustomConnection() {
        guard let url = URL(string: tm.customEndpoint) else {
            connectionTestResult = ConnectionTestResult(success: false, message: "Invalid URL")
            return
        }

        isTesting = true
        connectionTestResult = nil

        Task {
            do {
                let model = tm.customModel.isEmpty ? "default" : tm.customModel
                let body: [String: Any] = [
                    "model": model,
                    "messages": [["role": "user", "content": "Say hi"]],
                    "max_tokens": 5
                ]

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !tm.customAPIKey.isEmpty {
                    request.setValue("Bearer \(tm.customAPIKey)", forHTTPHeaderField: "Authorization")
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 10

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    connectionTestResult = ConnectionTestResult(success: false, message: "No response")
                    isTesting = false
                    return
                }

                if http.statusCode == 200 {
                    var detail = "Connected (HTTP 200)"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let responseModel = json["model"] as? String {
                        detail = "Connected — model: \(responseModel)"
                    }
                    connectionTestResult = ConnectionTestResult(success: true, message: detail)
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let short = body.prefix(100)
                    connectionTestResult = ConnectionTestResult(success: false, message: "HTTP \(http.statusCode): \(short)")
                }
            } catch {
                connectionTestResult = ConnectionTestResult(success: false, message: error.localizedDescription)
            }
            isTesting = false
        }
    }
}

private struct ConnectionTestResult {
    let success: Bool
    let message: String
}

import SwiftUI

/// Settings page for app configuration (AI provider, model, OAuth, etc).
struct SettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    var onBack: (() -> Void)? = nil

    @State private var apiKeyInput: String = ""
    @State private var showKey = false
    @State private var saved = false

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
                    oauthSection
                    aiProviderSection
                }
            }
        }
        .onAppear {
            apiKeyInput = tm.openaiAPIKey
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

            // Model picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)

                if tm.selectedProvider == .custom {
                    // Show custom model from Custom Providers config
                    if tm.customModel.isEmpty {
                        Text("Not configured — set up in Custom Providers")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(tm.customModel)
                            .font(.callout)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                } else {
                    Picker("", selection: $tm.selectedAIModel) {
                        ForEach(tm.selectedProvider.modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // API Key (if required and not using OAuth)
            if tm.selectedProvider.requiresAPIKey && !(tm.oauthManager.isAuthenticated && tm.selectedProvider == .openai) {
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
                            tm.openaiAPIKey = apiKeyInput
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }) {
                            Text(saved ? "Saved" : "Save")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput == tm.openaiAPIKey)

                        if !tm.openaiAPIKey.isEmpty {
                            Button(action: {
                                tm.openaiAPIKey = ""
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
                if !tm.customEndpoint.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using custom endpoint — configure in Custom Providers")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Set up your endpoint in Custom Providers first")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
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
}

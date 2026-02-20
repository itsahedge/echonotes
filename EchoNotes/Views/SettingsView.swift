import SwiftUI

/// Settings page for app configuration (AI provider, model, etc).
struct SettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    let onBack: () -> Void

    @State private var apiKeyInput: String = ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiProviderSection
                    oauthSection
                    aboutSection
                }
            }
        }
        .onAppear {
            apiKeyInput = tm.openaiAPIKey
        }
    }

    // MARK: - AI Provider Section

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Summarization", systemImage: "sparkles")
                .font(.subheadline.bold())

            Text("Choose an AI provider for meeting summaries. Your API key is stored locally and never sent anywhere except the provider's API.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Provider picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Picker("", selection: $tm.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: tm.selectedProvider) { _, newValue in
                    tm.selectedAIModel = newValue.defaultModel
                    // Clear key when switching providers (different key formats)
                    if newValue.requiresAPIKey && apiKeyInput.isEmpty {
                        apiKeyInput = ""
                    }
                }
            }

            // Model picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Picker("", selection: $tm.selectedAIModel) {
                    ForEach(tm.selectedProvider.modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
            }

            // API Key (if required)
            if tm.selectedProvider.requiresAPIKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField(tm.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            } else {
                                SecureField(tm.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            }
                        }
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.caption2)
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
                            Text(saved ? "Saved ✓" : "Save")
                                .font(.caption)
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
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }

                        Spacer()

                        if tm.isAIConfigured {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } else {
                // Ollama — no key needed, just check if it's running
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("No API key needed — make sure Ollama is running locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - OAuth Section

    private var oauthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sign In with Account", systemImage: "person.crop.circle")
                .font(.subheadline.bold())

            Text("Sign in with your existing subscription instead of an API key. Your ChatGPT Plus/Pro or Claude subscription includes API access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // OpenAI OAuth
            HStack(spacing: 10) {
                Button(action: {
                    // TODO: Implement OAuth PKCE flow (see issue #119)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                        Text("Sign in with ChatGPT")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .disabled(true) // Not yet implemented

                Button(action: {
                    // TODO: Implement Anthropic OAuth
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                        Text("Sign in with Claude")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .disabled(true) // Not yet implemented
            }

            Text("Coming soon — see [issue #119](https://github.com/itsahedge/echonotes/issues/119) for progress")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("About", systemImage: "info.circle")
                .font(.caption.bold())
            Text("EchoNotes — local-first meeting recorder with on-device transcription via WhisperKit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

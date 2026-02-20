import SwiftUI

/// Settings page for app configuration (AI features, etc).
struct SettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    let onBack: () -> Void

    @State private var apiKeyInput: String = ""
    @State private var showKey = false

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
                    // AI Summarization section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Summarization", systemImage: "sparkles")
                            .font(.caption.bold())

                        Text("Add an OpenAI API key to enable AI-powered meeting summaries after transcription.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Group {
                                if showKey {
                                    TextField("sk-...", text: $apiKeyInput)
                                } else {
                                    SecureField("sk-...", text: $apiKeyInput)
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
                            }) {
                                Text("Save")
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

                            if !tm.openaiAPIKey.isEmpty {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                    // About section
                    VStack(alignment: .leading, spacing: 4) {
                        Label("About", systemImage: "info.circle")
                            .font(.caption.bold())
                        Text("EchoNotes — local-first meeting recorder with on-device transcription via WhisperKit.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .onAppear {
            apiKeyInput = tm.openaiAPIKey
        }
    }
}

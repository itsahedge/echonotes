import SwiftUI

/// macOS Settings window with tabs for General, AI, Custom Providers, and About.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aiTab
                .tabItem { Label("AI Providers", systemImage: "sparkles") }
            customTab
                .tabItem { Label("Custom Providers", systemImage: "plus.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Transcription") {
                Picker("Mode", selection: $recorder.transcriptionModeRaw) {
                    ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if recorder.transcriptionMode == .postRecording {
                    Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                }
            }

            Section("Whisper Model") {
                Picker("Model", selection: $tm.selectedModel) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - AI Providers

    private var aiTab: some View {
        SettingsView(tm: tm)
            .padding()
    }

    // MARK: - Custom Providers

    private var customTab: some View {
        Form {
            Section {
                Text("Connect to any OpenAI-compatible API endpoint (llama.cpp, vLLM, LM Studio, text-generation-webui, etc).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Endpoint") {
                TextField("URL", text: $tm.customEndpoint, prompt: Text("http://localhost:8080/v1/chat/completions"))
                    .textFieldStyle(.roundedBorder)
            }

            Section("Model") {
                TextField("Model name", text: $tm.customModel, prompt: Text("e.g. qwen3.5-35b-a3b"))
                    .textFieldStyle(.roundedBorder)
                Text("The model name sent in the request body. Check your server's /v1/models endpoint for available models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API Key (optional)") {
                SecureField("API key", text: $tm.customAPIKey, prompt: Text("Leave empty if not required"))
                    .textFieldStyle(.roundedBorder)
                Text("Only needed if your server requires authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(action: {
                        tm.selectedProvider = .custom
                        tm.selectedAIModel = tm.customModel.isEmpty ? "default" : tm.customModel
                    }) {
                        Text(tm.selectedProvider == .custom ? "Active" : "Use This Provider")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tm.customEndpoint.isEmpty || tm.selectedProvider == .custom)

                    if tm.selectedProvider == .custom {
                        Label("Currently active", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("EchoNotes")
                .font(.title2.bold())
            Text("Local-first meeting recorder with on-device transcription via WhisperKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

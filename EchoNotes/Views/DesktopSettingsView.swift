import SwiftUI

/// macOS Settings window with tabs for General, AI, Custom Providers, and About.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTesting = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aiTab
                .tabItem { Label("AI Providers", systemImage: "sparkles") }
            customTab
                .tabItem { Label("Custom Providers", systemImage: "plus.circle") }
            knowledgeBaseTab
                .tabItem { Label("Knowledge Base", systemImage: "book.closed") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                HStack(spacing: 12) {
                    Button(action: { testConnection() }) {
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

                if let result = connectionTestResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        Text(result.message)
                            .font(.callout)
                            .foregroundColor(result.success ? .primary : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Knowledge Base

    @State private var knowledgeBaseFileCount: Int?

    private var knowledgeBaseTab: some View {
        Form {
            Section {
                Text("Point to a folder of markdown files (e.g., an Obsidian vault) to give AI summaries contextual knowledge about your project, team, and prior decisions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Folder Path") {
                HStack {
                    TextField("Path", text: $tm.knowledgeBasePath, prompt: Text("~/Documents/my-vault"))
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            tm.knowledgeBasePath = url.path
                            scanKnowledgeBase()
                        }
                    }
                }

                if let count = knowledgeBaseFileCount {
                    Label("\(count) markdown files found", systemImage: "doc.text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if !tm.knowledgeBasePath.isEmpty {
                    Label("Folder not found", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Include knowledge base context in AI summaries", isOn: $tm.useKnowledgeBase)
                    .disabled(tm.knowledgeBasePath.isEmpty)

                if tm.useKnowledgeBase && !tm.knowledgeBasePath.isEmpty {
                    Text("When generating a summary, EchoNotes will auto-discover relevant files from your knowledge base and include them as context for the AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { scanKnowledgeBase() }
    }

    private func scanKnowledgeBase() {
        guard !tm.knowledgeBasePath.isEmpty else {
            knowledgeBaseFileCount = nil
            return
        }
        let path = (tm.knowledgeBasePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            knowledgeBaseFileCount = nil
            return
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            knowledgeBaseFileCount = nil
            return
        }
        var count = 0
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "md" { count += 1 }
        }
        knowledgeBaseFileCount = count
    }

    // MARK: - About

    // MARK: - Test Connection

    private func testConnection() {
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
                    // Try to extract model info from response
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

private struct ConnectionTestResult {
    let success: Bool
    let message: String
}

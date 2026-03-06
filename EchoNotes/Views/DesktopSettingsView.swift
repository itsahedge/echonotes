import SwiftUI

/// Settings dashboard with sidebar navigation and content area.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var selectedSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case aiProviders = "AI Providers"
        case customProviders = "Custom Providers"
        case knowledgeBase = "Knowledge Base"
        case developer = "Developer"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .aiProviders: return "sparkles"
            case .customProviders: return "plus.circle"
            case .knowledgeBase: return "book.closed"
            case .developer: return "chevron.left.forwardslash.chevron.right"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                List(SettingsSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 180)

            Divider()

            // Content area
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            generalTab
        case .aiProviders:
            aiTab
        case .customProviders:
            customTab
        case .knowledgeBase:
            knowledgeBaseTab
        case .developer:
            developerTab
        case .about:
            aboutTab
        }
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

    // MARK: - Developer

    @ObservedObject private var debugLog = DebugLogger.shared

    private var developerTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debug Console")
                    .font(.headline)
                Spacer()
                Text("\(debugLog.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear") { debugLog.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if debugLog.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No log entries yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Logs appear here as you record, transcribe, and generate summaries.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(debugLog.entries) { entry in
                                debugLogRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: debugLog.entries.count) { _, _ in
                        if let last = debugLog.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private static let logTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func debugLogRow(_ entry: DebugLogger.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.logTimeFmt.string(from: entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(logLevelColor(entry.level))
                .frame(width: 36, alignment: .leading)

            Text(entry.category)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.purple)
                .frame(width: 100, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func logLevelColor(_ level: DebugLogger.Entry.Level) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
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
}

private struct ConnectionTestResult {
    let success: Bool
    let message: String
}

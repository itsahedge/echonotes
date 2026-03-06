import SwiftUI

/// Settings content view — renders the content for a given app section.
/// The sidebar navigation is handled by MainWindowView.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    let section: AppSection

    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(section.rawValue)
                .font(.title3.bold())
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 20)

            // Content
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch section {
        case .general:
            generalContent
        case .aiProviders:
            aiContent
        case .customProviders:
            customContent
        case .knowledgeBase:
            knowledgeBaseContent
        case .developer:
            developerContent
        case .about:
            aboutContent
        case .meetings:
            EmptyView()
        }
    }

    // MARK: - General

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsGroup("Transcription") {
                    settingsRow("Mode") {
                        Picker("", selection: $recorder.transcriptionModeRaw) {
                            ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }

                    if recorder.transcriptionMode == .postRecording {
                        settingsRow("Auto-transcribe") {
                            Toggle("", isOn: $recorder.autoTranscribe)
                                .labelsHidden()
                        }
                    }
                }

                settingsGroup("Whisper Model") {
                    settingsRow("Model") {
                        Picker("", selection: $tm.selectedModel) {
                            ForEach(WhisperModel.allCases, id: \.self) { model in
                                Text(model.rawValue).tag(model)
                            }
                        }
                        .frame(maxWidth: 200)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - AI Providers

    private var aiContent: some View {
        ScrollView {
            SettingsView(tm: tm)
                .padding(20)
        }
    }

    // MARK: - Custom Providers

    private var customContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to any OpenAI-compatible API endpoint (llama.cpp, vLLM, LM Studio, etc).")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                settingsGroup("Endpoint") {
                    TextField("URL", text: $tm.customEndpoint, prompt: Text("http://localhost:8080/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)
                }

                settingsGroup("Model") {
                    TextField("Model name", text: $tm.customModel, prompt: Text("e.g. qwen3.5-35b-a3b"))
                        .textFieldStyle(.roundedBorder)
                    Text("The model name sent in the request body.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                settingsGroup("API Key") {
                    SecureField("API key", text: $tm.customAPIKey, prompt: Text("Leave empty if not required"))
                        .textFieldStyle(.roundedBorder)
                    Text("Only needed if your server requires authentication.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
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
                }

                if tm.selectedProvider == .custom {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Selected as active provider in AI Providers")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("To use this provider, select \"Custom (OpenAI-compatible)\" in AI Providers.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
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
            .padding(20)
        }
    }

    // MARK: - Knowledge Base

    @State private var knowledgeBaseFileCount: Int?

    private var knowledgeBaseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Point to a folder of markdown files (e.g., an Obsidian vault) to give AI summaries contextual knowledge about your project.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                settingsGroup("Folder Path") {
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !tm.knowledgeBasePath.isEmpty {
                        Label("Folder not found", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                settingsGroup("Context Injection") {
                    settingsRow("Include in AI summaries") {
                        Toggle("", isOn: $tm.useKnowledgeBase)
                            .labelsHidden()
                            .disabled(tm.knowledgeBasePath.isEmpty)
                    }

                    if tm.useKnowledgeBase && !tm.knowledgeBasePath.isEmpty {
                        Text("Relevant vault files will be auto-discovered and included as context when generating summaries.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(20)
        }
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

    private var developerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("\(debugLog.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Clear") { debugLog.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if debugLog.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No log entries yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(debugLog.entries) { entry in
                                debugLogRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: debugLog.entries.count) { _, _ in
                        if let last = debugLog.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
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
                .foregroundStyle(.tertiary)

            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(logLevelColor(entry.level))
                .frame(width: 36, alignment: .leading)

            Text(entry.category)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.purple)
                .frame(width: 90, alignment: .leading)

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

    private var aboutContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("EchoNotes")
                .font(.title2.bold())
            Text("Local-first meeting recorder with on-device transcription via WhisperKit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared Components

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            content()
        }
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

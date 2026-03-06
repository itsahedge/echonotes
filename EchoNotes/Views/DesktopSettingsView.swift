import SwiftUI

/// Settings content view — renders the content for a given app section.
/// The sidebar navigation is handled by MainWindowView.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    let section: AppSection

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

}

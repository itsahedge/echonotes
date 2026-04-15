import SwiftUI

/// Unified app section for Craft-style sidebar navigation.
enum AppSection: String, CaseIterable, Identifiable {
    case meetings = "Meetings"
    case general = "General"
    case aiProviders = "AI Providers"

    case knowledgeBase = "Knowledge Base"
    case developer = "Developer"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meetings: return "list.bullet"
        case .general: return "gearshape"
        case .aiProviders: return "sparkles"

        case .knowledgeBase: return "book.closed"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .about: return "info.circle"
        }
    }

    var isSettings: Bool { self != .meetings }
}

/// Root view — Craft-style left sidebar with navigation sections + content area.
struct MainWindowView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var library: RecordingLibrary

    @State private var selectedSection: AppSection = .meetings
    @State private var selectedEntryID: URL?

    private var selectedEntry: RecordingEntry? {
        guard let id = selectedEntryID else { return nil }
        return library.entries.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            appSidebar
            Divider()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarContent
            }
        }
        .task {
            library.requestRefresh()
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            if isRecording {
                selectedSection = .meetings
                library.requestRefresh()
                if let url = recorder.lastRecordingURL {
                    selectedEntryID = url
                }
            } else {
                library.requestRefresh()
            }
        }
        .onChange(of: tm.isTranscribing) { _, isTranscribing in
            if !isTranscribing {
                library.requestRefresh()
                if let url = tm.transcript?.recordingURL {
                    selectedEntryID = url
                }
            }
        }
        .onChange(of: tm.isSummarizing) { _, isSummarizing in
            if !isSummarizing {
                library.requestRefresh()
            }
        }
    }

    // MARK: - Sidebar

    private var appSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EchoNotes")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(.meetings)
                        .padding(.bottom, 8)

                    sectionHeader("Configuration")
                    ForEach([AppSection.general, .aiProviders, .knowledgeBase], id: \.self) { section in
                        sidebarRow(section)
                    }

                    sectionHeader("Other")
                        .padding(.top, 12)
                    ForEach([AppSection.developer, .about], id: \.self) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            Spacer()
        }
        .frame(width: 190)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Button(action: { selectedSection = section }) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.callout)
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.callout)
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selectedSection == section
                    ? Color.secondary.opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch selectedSection {
        case .meetings:
            meetingsContent
        default:
            DesktopSettingsView(section: selectedSection)
        }
    }

    // MARK: - Meetings Content

    private var meetingsContent: some View {
        HStack(spacing: 0) {
            meetingListPanel
                .frame(width: 280)
            Divider()
            meetingDetailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var meetingListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search meetings...", text: $library.searchQuery)
                    .textFieldStyle(.plain)
                if !library.searchQuery.isEmpty {
                    Button(action: { library.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            if library.filteredEntries.isEmpty {
                Spacer()
                if library.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No recordings yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No results for \"\(library.searchQuery)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(library.filteredEntries, selection: $selectedEntryID) { entry in
                    MeetingRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(action: {
                                NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
                            }) {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            Divider()
                            Button(role: .destructive) {
                                library.delete(entry)
                                if selectedEntryID == entry.id {
                                    selectedEntryID = nil
                                }
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var meetingDetailPanel: some View {
        if recorder.isRecording || tm.isTranscribing || modelManager.isDownloading || modelManager.isLoading {
            ActiveRecordingView()
        } else if let entry = selectedEntry {
            RecordingDetailView(entry: entry)
        } else if let summary = tm.summary, let transcript = tm.transcript {
            SummaryView(summary: summary, recordingURL: transcript.recordingURL, onBack: {
                tm.summary = nil
            })
            .padding(20)
        } else if let transcript = tm.transcript {
            TranscriptDisplayView(transcript: transcript, onNew: {
                tm.reset()
                recorder.lastRecordingURL = nil
            }, onSummarize: !tm.isAIConfigured ? nil : {
                Task { await tm.summarize() }
            }, isSummarizing: tm.isSummarizing)
            .padding(20)
        } else if recorder.lastRecordingURL != nil {
            readyToTranscribeView
        } else {
            emptyStateView
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarContent: some View {
        if recorder.isRecording {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Recording")
                    .foregroundStyle(.red)
            }
        } else {
            Text("Ready")
                .foregroundStyle(.secondary)
        }

        if let entry = selectedEntry {
            Menu {
                if entry.hasTranscript {
                    Button(action: { copyTranscript(for: entry) }) {
                        Label("Copy Transcript", systemImage: "doc.on.doc")
                    }
                }
                if hasSummary(for: entry) {
                    Button(action: { copySummary(for: entry) }) {
                        Label("Copy Summary", systemImage: "doc.on.doc")
                    }
                }
                Divider()
                Button(action: {
                    NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        Picker("Mode", selection: $recorder.transcriptionModeRaw) {
            ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                Text(mode.rawValue).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)

        Button(action: {
            Task {
                if recorder.isRecording {
                    await recorder.stopRecording()
                } else {
                    await recorder.startRecording()
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                Text(recorder.isRecording ? "Stop" : "Record")
            }
        }
        .tint(recorder.isRecording ? .red : .accentColor)
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Ready to record")
                .font(.title2)
            Text("Start a call in any app, then hit Record.")
                .font(.body)
                .foregroundStyle(.secondary)

            if recorder.transcriptionMode == .postRecording {
                Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                    .font(.callout)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .frame(width: 280)
            } else {
                Text("Transcribes while you record")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if tm.isAIConfigured {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("AI summaries enabled")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyToTranscribeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Recording saved")
                .font(.title2)
            Text("Transcribe to get a text version of your call.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button(action: {
                guard let url = recorder.lastRecordingURL else { return }
                Task { await tm.transcribe(audioURL: url) }
            }) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text("Transcribe")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryURL(for entry: RecordingEntry) -> URL {
        entry.url.deletingPathExtension().appendingPathExtension("summary.json")
    }

    private func hasSummary(for entry: RecordingEntry) -> Bool {
        FileManager.default.fileExists(atPath: summaryURL(for: entry).path)
    }

    private func copyTranscript(for entry: RecordingEntry) {
        guard let transcript = entry.loadTranscript() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.toPlainText(), forType: .string)
    }

    private func copySummary(for entry: RecordingEntry) {
        let url = summaryURL(for: entry)
        guard let data = try? Data(contentsOf: url),
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.toMarkdown(), forType: .string)
    }
}

/// A single row in the meeting list.
private struct MeetingRow: View {
    let entry: RecordingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LibraryView.dateFormatter.string(from: entry.date))
                    .font(.body.bold())
                    .lineLimit(1)
                Spacer()
                Text(Transcript.formatTimestamp(entry.duration))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let preview = entry.transcriptPreview {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(entry.hasTranscript ? "Transcript available" : "Not transcribed")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

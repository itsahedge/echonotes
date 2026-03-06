import SwiftUI

/// Root view with NavigationSplitView — sidebar of recordings + detail area.
struct MainWindowView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var library: RecordingLibrary

    @State private var selectedEntryID: URL?
    @State private var showingSettings = false

    private var selectedEntry: RecordingEntry? {
        guard let id = selectedEntryID else { return nil }
        return library.entries.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedEntryID: $selectedEntryID)
        } detail: {
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showingSettings {
                    Divider()
                    DesktopSettingsView(onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showingSettings = false }
                        })
                        .frame(width: 520)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarContent
            }
        }
        .onAppear {
            library.scan()
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            if isRecording {
                // Scan + select the new entry as soon as recording starts
                library.scan()
                if let url = recorder.lastRecordingURL {
                    selectedEntryID = url
                }
            } else {
                // Re-scan after recording stops so duration/metadata updates
                library.scan()
            }
        }
        .onChange(of: tm.isTranscribing) { _, isTranscribing in
            if !isTranscribing {
                // Re-scan after transcription completes so transcript preview updates
                library.scan()
                // Auto-select the newly transcribed recording
                if let url = tm.transcript?.recordingURL {
                    selectedEntryID = url
                }
            }
        }
        .onChange(of: tm.isSummarizing) { _, isSummarizing in
            if !isSummarizing {
                // Re-scan after summary so the entry reflects updated state
                library.scan()
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if recorder.isRecording || tm.isTranscribing || modelManager.isDownloading || modelManager.isLoading {
            ActiveRecordingView()
        } else if let entry = selectedEntry {
            RecordingDetailView(entry: entry)
                .id(entry.id)
        } else if let summary = tm.summary, let transcript = tm.transcript {
            // Current-session flow: user just recorded → transcribed → summarized (no library entry selected)
            SummaryView(summary: summary, recordingURL: transcript.recordingURL, onBack: {
                tm.summary = nil
            })
            .padding(20)
        } else if let transcript = tm.transcript {
            // Current-session flow: user just recorded → transcribed (no library entry selected)
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
        // Recording status
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

        // Transcription mode picker
        Picker("Mode", selection: $recorder.transcriptionModeRaw) {
            ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                Text(mode.rawValue).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)

        // Settings
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showingSettings.toggle() } }) {
            Image(systemName: "gearshape")
        }
        .help(showingSettings ? "Close Settings" : "Settings")

        // Record / Stop button
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
}

import SwiftUI

/// The entire UI — coordinates state and delegates to specialized subviews.
/// Recording controls, level meters, and transcript display are extracted into separate components.
struct MenuBarView: View {
    @ObservedObject var recorder: RecordingEngine
    @ObservedObject var tm: TranscriptionManager
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var library: RecordingLibrary
    weak var delegate: AppDelegate?

    @State private var showingLibrary = false
    @State private var showingSettings = false
    @State private var selectedEntry: RecordingEntry?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(recorder.isRecording ? .red : .primary)
                Text("EchoNotes")
                    .font(.headline)
                Spacer()
                if recorder.isRecording {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("REC").font(.caption).foregroundStyle(.red)
                    }
                } else if !showingLibrary && !showingSettings {
                    HStack(spacing: 8) {
                        Button(action: {
                            library.scan()
                            showingLibrary = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Recording Library")

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                }
            }

            Divider()

            if showingSettings {
                SettingsView(tm: tm, onBack: { showingSettings = false })
            } else if showingLibrary {
                if let entry = selectedEntry {
                    RecordingDetailView(entry: entry, tm: tm, onBack: {
                        selectedEntry = nil
                    })
                } else {
                    LibraryView(library: library, onSelect: { entry in
                        selectedEntry = entry
                    }, onBack: {
                        showingLibrary = false
                        selectedEntry = nil
                    })
                }
            } else if recorder.isRecording {
                recordingView
            } else if tm.isTranscribing || modelManager.isDownloading || modelManager.isLoading {
                transcribingView
            } else if let summary = tm.summary, let transcript = tm.transcript {
                SummaryView(summary: summary, recordingURL: transcript.recordingURL, onBack: {
                    tm.summary = nil
                })
            } else if let transcript = tm.transcript {
                TranscriptDisplayView(transcript: transcript, onNew: {
                    tm.reset()
                    recorder.lastRecordingURL = nil
                }, onSummarize: tm.openaiAPIKey.isEmpty ? nil : {
                    Task { await tm.summarize() }
                }, isSummarizing: tm.isSummarizing)
            } else if recorder.lastRecordingURL != nil {
                readyToTranscribeView
            } else {
                idleView
            }

            // Error messages
            if let error = recorder.errorMessage ?? tm.error ?? modelManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            // Primary action button
            RecordingControlsView(recorder: recorder, delegate: delegate)

            // Quit button
            HStack {
                Spacer()
                Button("Quit") {
                    delegate?.removeEventMonitor()
                    NSApp.terminate(nil)
                }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
        .frame(minHeight: 280, maxHeight: 500)
    }

    // MARK: - State Views

    private var recordingView: some View {
        VStack(spacing: 12) {
            Text(Transcript.formatTimestamp(recorder.duration))
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                LevelMeterView(label: "System", level: recorder.systemLevel)
                LevelMeterView(label: "Mic", level: recorder.micLevel)
            }

            // Live transcript display
            if recorder.transcriptionMode == .live {
                liveTranscriptView
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var liveTranscriptView: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                if tm.streamingTranscriber.isProcessing {
                    ProgressView().controlSize(.mini)
                }
                Text("Live Transcript")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if tm.streamingTranscriber.segments.isEmpty {
                Text("Listening…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            // Only show the last 50 segments for performance
                            // Full array is preserved in StreamingTranscriber.segments for final transcript
                            ForEach(Array(recentSegments.enumerated()), id: \.offset) { idx, segment in
                                HStack(alignment: .top, spacing: 4) {
                                    if let speaker = segment.speaker {
                                        Text(speaker)
                                            .font(.caption2.bold())
                                            .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                    }
                                    Text(segment.cleanText)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(idx)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: tm.streamingTranscriber.segments.count) { _, newCount in
                        if newCount > 0 {
                            proxy.scrollTo(min(recentSegments.count - 1, 49), anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    /// Returns the last 50 segments for live display to avoid SwiftUI performance issues
    /// with long recordings. Full array is preserved for the final transcript.
    private var recentSegments: [TranscriptSegment] {
        let segments = tm.streamingTranscriber.segments
        let maxVisible = 50
        if segments.count > maxVisible {
            return Array(segments.suffix(maxVisible))
        }
        return segments
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ready to record")
                .font(.title3)
            Text("Start a call in any app, then hit record.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Transcription mode picker
            Picker("Transcription", selection: $recorder.transcriptionModeRaw) {
                ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption)

            if recorder.transcriptionMode == .postRecording {
                Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            } else {
                Text("Transcribes while you record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hint about AI summaries if key is configured
            if !tm.openaiAPIKey.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text("AI summaries enabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var readyToTranscribeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Recording saved")
                .font(.title3)
            Text("Transcribe to get a text version of your call.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                guard let url = recorder.lastRecordingURL else { return }
                Task { await tm.transcribe(audioURL: url) }
            }) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text("Transcribe")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var transcribingView: some View {
        VStack(spacing: 12) {
            if modelManager.isDownloading {
                Text("Downloading model…")
                    .font(.title3)
                ProgressView(value: modelManager.downloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(modelManager.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if modelManager.isLoading {
                Text("Loading model…")
                    .font(.title3)
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Transcribing…")
                    .font(.title3)
                ProgressView(value: tm.progress)
                    .progressViewStyle(.linear)
                Text("\(Int(tm.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: { tm.cancel() }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }

}

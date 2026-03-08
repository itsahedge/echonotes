import SwiftUI

/// Shows active recording state: timer, level meters, live transcript, or transcription progress.
struct ActiveRecordingView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        VStack(spacing: 20) {
            if recorder.isRecording {
                recordingView
            } else if modelManager.isDownloading {
                downloadingView
            } else if modelManager.isLoading {
                loadingModelView
            } else if tm.isTranscribing {
                transcribingView
            }

            // Error messages
            if let error = recorder.errorMessage ?? tm.error ?? modelManager.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 20) {
            // Show pause indicator and resume button
            if recorder.isPaused {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                    VStack {
                        Text("Recording Paused")
                            .font(.headline)
                        Text("Tap to resume")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            await recorder.resume()
                        }
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
            }

            Text(Transcript.formatTimestamp(recorder.duration + recorder.pauseDuration))
                .font(.system(size: 52, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            HStack(spacing: 24) {
                LevelMeterView(label: "System", level: recorder.systemLevel)
                LevelMeterView(label: "Mic", level: recorder.micLevel)
            }
            .frame(maxWidth: 400)

            if recorder.transcriptionMode == .live {
                liveTranscriptView
            }
        }
    }

    private var liveTranscriptView: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                if tm.streamingTranscriber.isProcessing {
                    ProgressView().controlSize(.small)
                }
                Text("Live Transcript")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if tm.streamingTranscriber.segments.isEmpty {
                Text("Listening...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tm.streamingTranscriber.segments, id: \.self) { segment in
                                HStack(alignment: .top, spacing: 6) {
                                    if let speaker = segment.speaker {
                                        Text(speaker)
                                            .font(.callout.bold())
                                            .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                    }
                                    Text(segment.cleanText)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .onChange(of: tm.streamingTranscriber.segments.count) { _, newCount in
                        if newCount > 0 {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var recentSegments: [TranscriptSegment] {
        let segments = tm.streamingTranscriber.segments
        let maxVisible = 50
        if segments.count > maxVisible {
            return Array(segments.suffix(maxVisible))
        }
        return segments
    }

    // MARK: - Progress States

    private var downloadingView: some View {
        VStack(spacing: 16) {
            Text("Downloading model...")
                .font(.title2)
            ProgressView(value: modelManager.downloadProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
            Text("\(Int(modelManager.downloadProgress * 100))%")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingModelView: some View {
        VStack(spacing: 16) {
            Text("Loading model...")
                .font(.title2)
            ProgressView()
                .controlSize(.regular)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 16) {
            Text("Transcribing...")
                .font(.title2)
            ProgressView(value: tm.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
            Text("\(Int(tm.progress * 100))%")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: { tm.cancel() }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

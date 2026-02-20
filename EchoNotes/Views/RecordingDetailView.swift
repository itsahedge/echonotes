import SwiftUI

/// Detail view for a single recording — shows metadata, transcript, and AI summary options.
struct RecordingDetailView: View {
    let entry: RecordingEntry
    @ObservedObject var tm: TranscriptionManager
    let onBack: () -> Void

    @State private var transcript: Transcript?
    @State private var summary: MeetingSummary?
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var showTranscript = false

    private var hasSummary: Bool {
        summary != nil || loadExistingSummary() != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                if showTranscript {
                    Text("Transcript")
                        .font(.headline)
                } else if summary != nil {
                    Text("Summary")
                        .font(.headline)
                } else {
                    Text("Recording")
                        .font(.headline)
                }
                Spacer()
            }

            if showTranscript, let transcript {
                // Full transcript view
                transcriptView(transcript)
            } else if let summary {
                // AI Summary view
                SummaryView(summary: summary, recordingURL: entry.url, onBack: {
                    self.summary = nil
                })
            } else {
                // Recording detail / info view
                recordingInfoView
            }
        }
        .onAppear {
            transcript = entry.loadTranscript()
            // Load existing summary if saved
            if let existing = loadExistingSummary() {
                summary = existing
            }
        }
    }

    // MARK: - Recording Info

    private var recordingInfoView: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Metadata card
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Details", systemImage: "info.circle")
                            .font(.caption.bold())

                        HStack {
                            Text("Date")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(LibraryView.dateFormatter.string(from: entry.date))
                                .font(.caption2)
                        }
                        HStack {
                            Text("Duration")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Transcript.formatTimestamp(entry.duration))
                                .font(.caption2.monospaced())
                        }
                        HStack {
                            Text("File")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.filename)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let transcript {
                            HStack {
                                Text("Segments")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(transcript.segments.count)")
                                    .font(.caption2)
                            }
                            let hasSpeakers = transcript.segments.contains { $0.speaker != nil }
                            if hasSpeakers {
                                HStack {
                                    Text("Speakers")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    HStack(spacing: 6) {
                                        ForEach([Speaker.user, .remote], id: \.rawValue) { speaker in
                                            Label(speaker.rawValue, systemImage: speaker.icon)
                                                .font(.caption2)
                                                .foregroundStyle(speaker.color)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                    // Transcript preview
                    if let preview = entry.transcriptPreview {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Transcript Preview", systemImage: "text.quote")
                                .font(.caption.bold())
                            Text(preview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // Summary status
                    if let existingSummary = loadExistingSummary() {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("AI Summary", systemImage: "sparkles")
                                .font(.caption.bold())
                            Text(existingSummary.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(8)
                        .onTapGesture {
                            summary = existingSummary
                        }
                    }
                }
            }

            // Action buttons
            VStack(spacing: 6) {
                if entry.hasTranscript {
                    Button(action: { showTranscript = true }) {
                        HStack {
                            Image(systemName: "text.quote")
                            Text("View Transcript")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                if loadExistingSummary() != nil {
                    Button(action: { summary = loadExistingSummary() }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("View Summary")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                } else if !tm.openaiAPIKey.isEmpty && entry.hasTranscript {
                    Button(action: { generateSummary() }) {
                        HStack {
                            if isSummarizing {
                                ProgressView().controlSize(.mini)
                                Text("Generating…")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Generate Summary with AI")
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSummarizing)
                } else if tm.openaiAPIKey.isEmpty && entry.hasTranscript {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("Add an API key in Settings to enable AI summaries")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                if let error = summaryError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            // Utility buttons
            HStack(spacing: 8) {
                Button(action: {
                    NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
                }) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Transcript View

    private func transcriptView(_ transcript: Transcript) -> some View {
        TranscriptDisplayView(transcript: transcript, onNew: {
            showTranscript = false
        }, onSummarize: (!tm.openaiAPIKey.isEmpty && loadExistingSummary() == nil) ? {
            showTranscript = false
            generateSummary()
        } : nil, isSummarizing: isSummarizing)
    }

    // MARK: - Summary Generation

    private func generateSummary() {
        guard let transcript, !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil

        Task {
            do {
                let service = AIService()
                let config = AIService.Configuration(apiKey: tm.openaiAPIKey)
                let text = transcript.toPlainText()
                let result = try await service.summarize(transcript: text, config: config)

                // Save to disk
                let mdURL = entry.url.deletingPathExtension().appendingPathExtension("md")
                try result.toMarkdown().write(to: mdURL, atomically: true, encoding: .utf8)

                let jsonSummaryURL = entry.url.deletingPathExtension().appendingPathExtension("summary.json")
                let encoded = try JSONEncoder().encode(result)
                try encoded.write(to: jsonSummaryURL, options: .atomic)

                summary = result
            } catch {
                summaryError = error.localizedDescription
            }
            isSummarizing = false
        }
    }

    // MARK: - Helpers

    private func loadExistingSummary() -> MeetingSummary? {
        let jsonURL = entry.url.deletingPathExtension().appendingPathExtension("summary.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data) else {
            return nil
        }
        return summary
    }
}

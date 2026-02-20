import SwiftUI

/// Detail view for a single recording — shows full transcript with AI summary option.
struct RecordingDetailView: View {
    let entry: RecordingEntry
    @ObservedObject var tm: TranscriptionManager
    let onBack: () -> Void

    @State private var transcript: Transcript?
    @State private var summary: MeetingSummary?
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var showingSummary = false

    private var existingSummary: MeetingSummary? {
        let jsonURL = entry.url.deletingPathExtension().appendingPathExtension("summary.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let result = try? JSONDecoder().decode(MeetingSummary.self, from: data) else {
            return nil
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().padding(.bottom, 8)

            if showingSummary, let summary {
                summaryContentView(summary)
            } else {
                mainContentView
            }
        }
        .onAppear {
            transcript = entry.loadTranscript()
            if let existing = existingSummary {
                summary = existing
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: {
                if showingSummary {
                    showingSummary = false
                } else {
                    onBack()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(showingSummary ? "AI Summary" : LibraryView.dateFormatter.string(from: entry.date))
                    .font(.caption.bold())
                Text(Transcript.formatTimestamp(entry.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Context menu
            Menu {
                Button(action: {
                    NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                if let transcript {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcript.toPlainText(), forType: .string)
                    }) {
                        Label("Copy Transcript", systemImage: "doc.on.doc")
                    }
                }
                if let summary {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.toMarkdown(), forType: .string)
                    }) {
                        Label("Copy Summary", systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Main Content (Transcript + AI button)

    private var mainContentView: some View {
        VStack(spacing: 8) {
            // Transcript — this is the main content
            if let transcript {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let hasSpeakers = transcript.segments.contains { $0.speaker != nil }

                        if hasSpeakers {
                            // Speaker legend
                            HStack(spacing: 8) {
                                ForEach([Speaker.user, .remote], id: \.rawValue) { speaker in
                                    Label(speaker.rawValue, systemImage: speaker.icon)
                                        .font(.caption2)
                                        .foregroundStyle(speaker.color)
                                }
                            }
                            .padding(.bottom, 4)

                            // Diarized transcript
                            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                                let text = segment.cleanText
                                if !text.isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        if let speaker = segment.speaker {
                                            Text(speaker)
                                                .font(.caption2.bold())
                                                .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                                .frame(width: 32, alignment: .trailing)
                                        }
                                        Text(text)
                                            .font(.caption)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        } else {
                            // Plain transcript
                            Text(transcript.toPlainText())
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "text.badge.xmark")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No transcript available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            // Bottom bar — AI summary button
            if entry.hasTranscript {
                Divider()

                if let error = summaryError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    if summary != nil || existingSummary != nil {
                        // Has a summary — show view + regenerate
                        Button(action: {
                            if let s = summary ?? existingSummary {
                                self.summary = s
                                showingSummary = true
                            }
                        }) {
                            Label("View Summary", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { generateSummary() }) {
                            if isSummarizing {
                                ProgressView().controlSize(.mini)
                            } else {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isSummarizing)
                    } else if !tm.openaiAPIKey.isEmpty {
                        // No summary, has API key
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
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSummarizing)
                    } else {
                        // No API key
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("Add API key in Settings for AI summaries")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Summary Content

    private func summaryContentView(_ summary: MeetingSummary) -> some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary.summary)
                        .font(.caption)

                    if !summary.actionItems.isEmpty {
                        sectionView(title: "Action Items", icon: "checkmark.circle", items: summary.actionItems)
                    }
                    if !summary.keyDecisions.isEmpty {
                        sectionView(title: "Key Decisions", icon: "star.fill", items: summary.keyDecisions)
                    }
                    if !summary.openQuestions.isEmpty {
                        sectionView(title: "Open Questions", icon: "questionmark.circle", items: summary.openQuestions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.toMarkdown(), forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }

                Button(action: { generateSummary() }) {
                    if isSummarizing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .disabled(isSummarizing)

                Spacer()
            }
        }
    }

    private func sectionView(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 4) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.caption)
                }
            }
        }
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

                let mdURL = entry.url.deletingPathExtension().appendingPathExtension("md")
                try result.toMarkdown().write(to: mdURL, atomically: true, encoding: .utf8)

                let jsonSummaryURL = entry.url.deletingPathExtension().appendingPathExtension("summary.json")
                let encoded = try JSONEncoder().encode(result)
                try encoded.write(to: jsonSummaryURL, options: .atomic)

                summary = result
                showingSummary = true
            } catch {
                summaryError = error.localizedDescription
            }
            isSummarizing = false
        }
    }
}

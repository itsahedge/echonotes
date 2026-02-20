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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    if showTranscript {
                        showTranscript = false
                    } else if summary != nil {
                        summary = nil
                    } else {
                        onBack()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Text(headerTitle)
                    .font(.headline)
                Spacer()

                // Context menu for file operations
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
            .padding(.bottom, 12)

            // Content
            if showTranscript, let transcript {
                transcriptContentView(transcript)
            } else if let summary {
                summaryContentView(summary)
            } else {
                detailContentView
            }
        }
        .onAppear {
            transcript = entry.loadTranscript()
            if let existing = loadExistingSummary() {
                // Don't auto-navigate to summary, just cache it
            }
        }
    }

    private var headerTitle: String {
        if showTranscript { return "Transcript" }
        if summary != nil { return "AI Summary" }
        return "Recording"
    }

    // MARK: - Detail Content

    private var detailContentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Date & Duration hero
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LibraryView.dateFormatter.string(from: entry.date))
                            .font(.title3.bold())
                        HStack(spacing: 12) {
                            Label(Transcript.formatTimestamp(entry.duration), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let transcript {
                                Label("\(transcript.segments.count) segments", systemImage: "text.alignleft")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let transcript {
                            let hasSpeakers = transcript.segments.contains { $0.speaker != nil }
                            if hasSpeakers {
                                HStack(spacing: 8) {
                                    ForEach([Speaker.user, .remote], id: \.rawValue) { speaker in
                                        Label(speaker.rawValue, systemImage: speaker.icon)
                                            .font(.caption)
                                            .foregroundStyle(speaker.color)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    Divider()

                    // Transcript preview
                    if let transcript {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Transcript", systemImage: "text.quote")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(action: { showTranscript = true }) {
                                    Text("View All →")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }

                            // Show first several segments as preview
                            VStack(alignment: .leading, spacing: 3) {
                                let previewSegments = Array(transcript.segments.prefix(8))
                                ForEach(Array(previewSegments.enumerated()), id: \.offset) { _, segment in
                                    let text = segment.cleanText
                                    if !text.isEmpty {
                                        if let speaker = segment.speaker {
                                            HStack(alignment: .top, spacing: 4) {
                                                Text(speaker + ":")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                                Text(text)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text(text)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if transcript.segments.count > 8 {
                                    Text("… \(transcript.segments.count - 8) more segments")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .italic()
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    } else if !entry.hasTranscript {
                        VStack(spacing: 6) {
                            Image(systemName: "text.badge.xmark")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text("No transcript available")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }

                    // AI Summary section
                    if let existingSummary = loadExistingSummary() {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("AI Summary", systemImage: "sparkles")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(action: { summary = existingSummary }) {
                                    Text("View →")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(existingSummary.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            if !existingSummary.actionItems.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.caption2)
                                    Text("\(existingSummary.actionItems.count) action items")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .onTapGesture { summary = existingSummary }
                    }
                }
            }

            Spacer(minLength: 8)

            // Action buttons at bottom
            VStack(spacing: 8) {
                if let error = summaryError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                if entry.hasTranscript {
                    if loadExistingSummary() == nil {
                        if !tm.openaiAPIKey.isEmpty {
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
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSummarizing)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("Add an API key in Settings to enable AI summaries")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript Content

    private func transcriptContentView(_ transcript: Transcript) -> some View {
        TranscriptDisplayView(transcript: transcript, onNew: {
            showTranscript = false
        }, onSummarize: (!tm.openaiAPIKey.isEmpty && loadExistingSummary() == nil) ? {
            showTranscript = false
            generateSummary()
        } : nil, isSummarizing: isSummarizing)
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

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.toMarkdown(), forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }

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
              let result = try? JSONDecoder().decode(MeetingSummary.self, from: data) else {
            return nil
        }
        return result
    }
}

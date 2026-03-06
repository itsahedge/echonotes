import SwiftUI

/// Detail view for a single recording — shows full transcript with AI summary option.
struct RecordingDetailView: View {
    let entry: RecordingEntry
    @EnvironmentObject var tm: TranscriptionManager

    @State private var transcript: Transcript?
    @State private var summary: MeetingSummary?
    @State private var isSummarizing = false
    @State private var summaryError: String?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(LibraryView.dateFormatter.string(from: entry.date))
                        .font(.title2.bold())
                    Text(Transcript.formatTimestamp(entry.duration))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // AI Summary section
                if let summary {
                    summarySection(summary)
                } else if entry.hasTranscript {
                    aiButtonSection
                }

                // Full Transcript
                if let transcript {
                    transcriptSection(transcript)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.badge.xmark")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No transcript available")
                            .font(.body)
                            .foregroundStyle(.tertiary)

                        Button(action: {
                            Task { await tm.transcribe(audioURL: entry.url) }
                        }) {
                            HStack {
                                Image(systemName: "text.bubble")
                                Text("Transcribe")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tm.isTranscribing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Context menu actions
                Menu {
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
        }
        .onAppear {
            transcript = entry.loadTranscript()
            if let existing = existingSummary {
                summary = existing
            }
        }
        .onChange(of: tm.isTranscribing) { _, isTranscribing in
            if !isTranscribing {
                // Reload transcript after transcription completes
                transcript = entry.loadTranscript()
            }
        }
    }

    // MARK: - AI Summary Button

    @ViewBuilder
    private var aiButtonSection: some View {
        if let error = summaryError {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
        }

        if tm.isAIConfigured {
            Button(action: { generateSummary() }) {
                HStack {
                    if isSummarizing {
                        ProgressView().controlSize(.small)
                        Text("Generating...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Ask EchoNotes")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSummarizing)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Add API key in Settings for AI summaries")
            }
            .font(.callout)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary card
            summaryCard(
                icon: "doc.text",
                title: "Summary",
                color: .blue
            ) {
                Text(summary.summary)
                    .font(.body)
                    .lineSpacing(4)
            }

            if !summary.actionItems.isEmpty {
                summaryCard(
                    icon: "checkmark.circle",
                    title: "Action Items",
                    color: .green
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.actionItems, id: \.self) { item in
                            bulletItem(item)
                        }
                    }
                }
            }

            if !summary.keyDecisions.isEmpty {
                summaryCard(
                    icon: "star.fill",
                    title: "Key Decisions",
                    color: .orange
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.keyDecisions, id: \.self) { item in
                            bulletItem(item)
                        }
                    }
                }
            }

            if !summary.openQuestions.isEmpty {
                summaryCard(
                    icon: "questionmark.circle",
                    title: "Open Questions",
                    color: .purple
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.openQuestions, id: \.self) { item in
                            bulletItem(item)
                        }
                    }
                }
            }

            // Regenerate button
            Button(action: { generateSummary() }) {
                if isSummarizing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSummarizing)
        }
    }

    private func summaryCard<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Transcript Section

    @State private var showTranscript = false

    private func transcriptSection(_ transcript: Transcript) -> some View {
        let hasSpeakers = transcript.segments.contains { $0.speaker != nil }

        return VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { showTranscript.toggle() } }) {
                HStack {
                    Label("Full Transcript", systemImage: "text.justify.leading")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: showTranscript ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showTranscript {
                VStack(alignment: .leading, spacing: 6) {
                    if hasSpeakers {
                        HStack(spacing: 12) {
                            ForEach([Speaker.user, .remote], id: \.rawValue) { speaker in
                                Label(speaker.rawValue, systemImage: speaker.icon)
                                    .font(.callout)
                                    .foregroundStyle(speaker.color)
                            }
                        }
                        .padding(.bottom, 4)

                        ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                            let text = segment.cleanText
                            if !text.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    if let speaker = segment.speaker {
                                        Text(speaker)
                                            .font(.callout.bold())
                                            .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                            .frame(width: 48, alignment: .trailing)
                                    }
                                    Text(text)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    } else {
                        Text(transcript.toPlainText())
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Summary Generation

    private func generateSummary() {
        guard let transcript, !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        let debugLog = DebugLogger.shared

        Task {
            do {
                let service = AIService()
                let config = tm.aiConfiguration()
                let text = transcript.toPlainText()
                debugLog.info("Summarizing with \(config.provider.rawValue) (\(config.model))", category: "AI")

                // Build knowledge base context if enabled
                var kbContext: String?
                if tm.useKnowledgeBase, !tm.knowledgeBasePath.isEmpty {
                    debugLog.info("Loading knowledge base from: \(tm.knowledgeBasePath)", category: "KnowledgeBase")
                    let kbService = KnowledgeBaseService()
                    kbContext = kbService.buildContext(vaultPath: tm.knowledgeBasePath, transcript: text)
                    if let ctx = kbContext {
                        debugLog.info("Injecting \(ctx.count) chars of vault context into prompt", category: "KnowledgeBase")
                    } else {
                        debugLog.warning("No relevant context found in vault", category: "KnowledgeBase")
                    }
                }

                let result = try await service.summarize(transcript: text, config: config, knowledgeBaseContext: kbContext)

                let mdURL = entry.url.deletingPathExtension().appendingPathExtension("md")
                try result.toMarkdown().write(to: mdURL, atomically: true, encoding: .utf8)

                let jsonSummaryURL = entry.url.deletingPathExtension().appendingPathExtension("summary.json")
                let encoded = try JSONEncoder().encode(result)
                try encoded.write(to: jsonSummaryURL, options: .atomic)

                debugLog.info("Summary generated successfully", category: "AI")
                summary = result
            } catch {
                debugLog.error("Summary failed: \(error.localizedDescription)", category: "AI")
                summaryError = error.localizedDescription
            }
            isSummarizing = false
        }
    }
}

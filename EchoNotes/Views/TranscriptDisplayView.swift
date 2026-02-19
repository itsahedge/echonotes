import SwiftUI

/// Displays a completed transcript with copy and open file actions.
struct TranscriptDisplayView: View {
    let transcript: Transcript
    let onNew: () -> Void
    var onSummarize: (() -> Void)? = nil
    var isSummarizing: Bool = false
    
    /// Whether this transcript has any speaker labels.
    private var hasSpeakers: Bool {
        transcript.segments.contains { $0.speaker != nil }
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                if hasSpeakers {
                    diarizedTranscriptView
                } else {
                    Text(transcript.toPlainText())
                        .font(.system(.caption))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: .infinity)

            // Speaker legend
            if hasSpeakers {
                HStack(spacing: 12) {
                    ForEach([Speaker.user, .remote], id: \.rawValue) { speaker in
                        Label(speaker.rawValue, systemImage: speaker.icon)
                            .font(.caption2)
                            .foregroundStyle(speaker.color)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.toPlainText(), forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }

                Button(action: {
                    let txtURL = transcript.recordingURL.deletingPathExtension().appendingPathExtension("txt")
                    if FileManager.default.fileExists(atPath: txtURL.path) {
                        NSWorkspace.shared.selectFile(txtURL.path, inFileViewerRootedAtPath: txtURL.deletingLastPathComponent().path)
                    }
                }) {
                    Label("Open File", systemImage: "doc.text")
                        .font(.caption)
                }

                if let onSummarize {
                    Button(action: onSummarize) {
                        if isSummarizing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Label("Summarize", systemImage: "sparkles")
                                .font(.caption)
                        }
                    }
                    .disabled(isSummarizing)
                }

                Spacer()

                Button(action: onNew) {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
            }
        }
    }

    private var diarizedTranscriptView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                let text = segment.cleanText
                if !text.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        if let speaker = segment.speaker {
                            Text(speaker)
                                .font(.caption2.bold())
                                .foregroundStyle(Speaker(rawValue: speaker)?.color ?? .primary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        Text(text)
                            .font(.system(.caption))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

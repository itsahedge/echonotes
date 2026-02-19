import SwiftUI

/// Displays a completed transcript with copy and open file actions.
struct TranscriptDisplayView: View {
    let transcript: Transcript
    let onNew: () -> Void
    
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
                    Label("You", systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Label("Them", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
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
                                .foregroundStyle(speaker == "You" ? .blue : .green)
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

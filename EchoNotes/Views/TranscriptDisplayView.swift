import SwiftUI

/// Displays a completed transcript with copy and open file actions.
struct TranscriptDisplayView: View {
    let transcript: Transcript
    let onNew: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(transcript.toTimestampedText())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)

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
}

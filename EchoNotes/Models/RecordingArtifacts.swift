import Foundation

/// Resolves where a recording's sidecar artifacts (transcript, summary) live.
///
/// Two layouts exist:
/// - **Session folders** (current): `transcript.json`, `transcript.txt`,
///   `summary.json`, and `summary.md` inside the folder, next to `mic.caf`
///   and `system.caf`.
/// - **Legacy flat recordings**: `recording-X.m4a` with siblings
///   `recording-X.json`, `.txt`, `.summary.json`, and `.md`.
///
/// A session folder never has a path extension and legacy recordings always
/// end in `.m4a`, so the extension distinguishes the layouts even for URLs
/// decoded from persisted transcript JSON (where directory-ness is lost).
struct RecordingArtifacts: Sendable {
    let transcriptJSON: URL
    let transcriptText: URL
    let summaryJSON: URL
    let summaryMarkdown: URL

    static func isSessionDirectory(_ url: URL) -> Bool {
        url.pathExtension.isEmpty
    }

    init(recordingURL: URL) {
        if Self.isSessionDirectory(recordingURL) {
            transcriptJSON = recordingURL.appendingPathComponent("transcript.json")
            transcriptText = recordingURL.appendingPathComponent("transcript.txt")
            summaryJSON = recordingURL.appendingPathComponent("summary.json")
            summaryMarkdown = recordingURL.appendingPathComponent("summary.md")
        } else {
            let base = recordingURL.deletingPathExtension()
            transcriptJSON = base.appendingPathExtension("json")
            transcriptText = base.appendingPathExtension("txt")
            summaryJSON = base.appendingPathExtension("summary.json")
            summaryMarkdown = base.appendingPathExtension("md")
        }
    }
}

import SwiftUI

/// Displays a structured AI meeting summary.
struct SummaryView: View {
    let summary: MeetingSummary
    let recordingURL: URL
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Meeting Notes")
                    .font(.caption.bold())
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Summary
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

                Button(action: {
                    let mdURL = recordingURL.deletingPathExtension().appendingPathExtension("md")
                    if FileManager.default.fileExists(atPath: mdURL.path) {
                        NSWorkspace.shared.selectFile(mdURL.path, inFileViewerRootedAtPath: mdURL.deletingLastPathComponent().path)
                    }
                }) {
                    Label("Open File", systemImage: "doc.text")
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
}

import Foundation

/// An action item extracted from meeting notes.
struct ActionItem: Codable, Sendable, Equatable {
    let text: String
    let assignee: String?
}

/// Structured meeting notes generated from a transcript by AI.
struct MeetingNotes: Codable, Sendable, Equatable {
    let summary: String
    let keyDecisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]

    /// Format as Markdown for export / clipboard.
    func toMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Meeting Notes")
        lines.append("")

        lines.append("## Summary")
        lines.append(summary)
        lines.append("")

        if !keyDecisions.isEmpty {
            lines.append("## Key Decisions")
            for decision in keyDecisions {
                lines.append("- \(decision)")
            }
            lines.append("")
        }

        if !actionItems.isEmpty {
            lines.append("## Action Items")
            for item in actionItems {
                if let assignee = item.assignee, !assignee.isEmpty {
                    lines.append("- **\(assignee):** \(item.text)")
                } else {
                    lines.append("- \(item.text)")
                }
            }
            lines.append("")
        }

        if !openQuestions.isEmpty {
            lines.append("## Open Questions")
            for question in openQuestions {
                lines.append("- \(question)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Save as `.notes.md` alongside the recording file.
    func save(alongside recordingURL: URL) throws {
        let basePath = recordingURL.deletingPathExtension()
        let notesURL = basePath.appendingPathExtension("notes.md")
        try toMarkdown().write(to: notesURL, atomically: true, encoding: .utf8)
    }
}

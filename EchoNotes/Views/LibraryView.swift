import SwiftUI

/// Displays a browsable list of past recordings.
struct LibraryView: View {
    @ObservedObject var library: RecordingLibrary
    let onSelect: (RecordingEntry) -> Void
    let onBack: () -> Void

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Library")
                    .font(.headline)
                Spacer()
                Text("\(library.entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcripts…", text: $library.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !library.searchQuery.isEmpty {
                    Button(action: { library.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            if library.filteredEntries.isEmpty {
                Spacer()
                if library.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No recordings yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No results for \"\(library.searchQuery)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(library.filteredEntries) { entry in
                            RecordingRow(entry: entry, onSelect: {
                                onSelect(entry)
                            }, onDelete: {
                                library.delete(entry)
                            })
                        }
                    }
                }
            }
        }
    }
}

/// A single row in the library list.
private struct RecordingRow: View {
    let entry: RecordingEntry
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(LibraryView.dateFormatter.string(from: entry.date))
                        .font(.caption.bold())
                    Spacer()
                    Text(Transcript.formatTimestamp(entry.duration))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let preview = entry.transcriptPreview {
                    Text(preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(entry.hasTranscript ? "Transcript available" : "Not transcribed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
            }) {
                Label("Show in Finder", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

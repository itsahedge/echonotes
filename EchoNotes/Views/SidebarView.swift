import SwiftUI

/// Sidebar listing past recordings with search.
struct SidebarView: View {
    @Environment(RecordingLibrary.self) private var library
    @Binding var selectedEntryID: URL?

    var body: some View {
        @Bindable var library = library
        return VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search meetings...", text: $library.searchQuery)
                    .textFieldStyle(.plain)
                if !library.searchQuery.isEmpty {
                    Button(action: { library.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            if library.filteredEntries.isEmpty {
                Spacer()
                if library.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No recordings yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No results for \"\(library.searchQuery)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(library.filteredEntries, selection: $selectedEntryID) { entry in
                    SidebarRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(action: {
                                NSWorkspace.shared.selectFile(entry.url.path, inFileViewerRootedAtPath: entry.url.deletingLastPathComponent().path)
                            }) {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            Divider()
                            Button(role: .destructive) {
                                library.delete(entry)
                                if selectedEntryID == entry.id {
                                    selectedEntryID = nil
                                }
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .navigationTitle("Meetings")
    }
}

/// A single row in the sidebar.
private struct SidebarRow: View {
    let entry: RecordingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LibraryView.dateFormatter.string(from: entry.date))
                    .font(.body.bold())
                    .lineLimit(1)
                Spacer()
                Text(Transcript.formatTimestamp(entry.duration))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let preview = entry.transcriptPreview {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(entry.hasTranscript ? "Transcript available" : "Not transcribed")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

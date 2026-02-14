import SwiftUI

/// The entire UI — start/stop button with duration, level meters, and transcription controls.
struct MenuBarView: View {
    @ObservedObject var recorder: RecordingEngine
    weak var delegate: AppDelegate?
    @State private var showSettings = false

    private var tm: TranscriptionManager { recorder.transcriptionManager }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(recorder.isRecording ? .red : .primary)
                Text("EchoNotes")
                    .font(.headline)
                Spacer()
                if recorder.isRecording {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("REC").font(.caption).foregroundStyle(.red)
                    }
                }
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if showSettings {
                settingsView
            } else if recorder.isRecording {
                recordingView
            } else if tm.isTranscribing || tm.isDownloadingModel {
                transcribingView
            } else if let transcript = tm.transcript {
                transcriptResultView(transcript)
            } else if recorder.lastRecordingURL != nil {
                readyToTranscribeView
            } else {
                idleView
            }

            // Error messages
            if let error = recorder.errorMessage ?? tm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Primary action button
            primaryButton

            // Quit button
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
        .frame(minHeight: 280, maxHeight: 500)
    }

    // MARK: - State Views

    private var recordingView: some View {
        VStack(spacing: 12) {
            Text(formatDuration(recorder.duration))
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                levelMeter(label: "System", level: recorder.systemLevel)
                levelMeter(label: "Mic", level: recorder.micLevel)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ready to record")
                .font(.title3)
            Text("Start a call in any app, then hit record.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(maxHeight: .infinity)
    }

    private var readyToTranscribeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Recording saved")
                .font(.title3)
            Text("Transcribe to get a text version of your call.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                guard let url = recorder.lastRecordingURL else { return }
                Task { await tm.transcribe(audioURL: url) }
            }) {
                HStack {
                    Image(systemName: "text.bubble")
                    Text("Transcribe")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var transcribingView: some View {
        VStack(spacing: 12) {
            if tm.isDownloadingModel {
                Text("Downloading model…")
                    .font(.title3)
                ProgressView(value: tm.downloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(tm.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Transcribing…")
                    .font(.title3)
                ProgressView(value: tm.progress)
                    .progressViewStyle(.linear)
                Text("\(Int(tm.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: { tm.cancel() }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }

    private func transcriptResultView(_ transcript: Transcript) -> some View {
        VStack(spacing: 8) {
            if let notes = tm.meetingNotes {
                meetingNotesView(notes)
            } else {
                ScrollView {
                    Text(transcript.toTimestampedText())
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    if let notes = tm.meetingNotes {
                        NSPasteboard.general.setString(notes.toMarkdown(), forType: .string)
                    } else {
                        NSPasteboard.general.setString(transcript.toPlainText(), forType: .string)
                    }
                }) {
                    Label(tm.meetingNotes != nil ? "Copy Notes" : "Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }

                Button(action: {
                    let txtURL = transcript.recordingURL.deletingPathExtension().appendingPathExtension("txt")
                    NSWorkspace.shared.selectFile(txtURL.path, inFileViewerRootedAtPath: txtURL.deletingLastPathComponent().path)
                }) {
                    Label("Open File", systemImage: "doc.text")
                        .font(.caption)
                }

                Spacer()

                Button(action: { tm.reset() }) {
                    Label("New", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
            }

            // AI notes buttons
            if tm.oauthManager.isSignedIn && tm.meetingNotes == nil {
                Divider()
                if tm.isGeneratingNotes {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Generating notes…").font(.caption)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: { Task { await tm.generateNotes() } }) {
                            Label("Generate Meeting Notes", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)

                    }
                }
            }
        }
    }

    private func meetingNotesView(_ notes: MeetingNotes) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Summary").font(.caption.bold())
                Text(notes.summary).font(.caption)

                if !notes.keyDecisions.isEmpty {
                    Divider()
                    Text("Key Decisions").font(.caption.bold())
                    ForEach(notes.keyDecisions, id: \.self) { decision in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•").font(.caption)
                            Text(decision).font(.caption)
                        }
                    }
                }

                if !notes.actionItems.isEmpty {
                    Divider()
                    Text("Action Items").font(.caption.bold())
                    ForEach(Array(notes.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("☐").font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.text).font(.caption)
                                if let assignee = item.assignee, !assignee.isEmpty {
                                    Text("→ \(assignee)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !notes.openQuestions.isEmpty {
                    Divider()
                    Text("Open Questions").font(.caption.bold())
                    ForEach(notes.openQuestions, id: \.self) { question in
                        HStack(alignment: .top, spacing: 4) {
                            Text("?").font(.caption).foregroundStyle(.orange)
                            Text(question).font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity)
    }

    private var settingsView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Settings").font(.title3)
                Spacer()
                Button(action: { showSettings = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // OpenAI connection
            HStack {
                Image(systemName: "brain")
                Text("OpenAI").font(.body)
                Spacer()
                if tm.oauthManager.isSignedIn {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if tm.oauthManager.isSignedIn {
                Button(action: { tm.oauthManager.signOut() }) {
                    Text("Sign Out")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: { Task { try? await tm.oauthManager.performSignIn() } }) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Sign in with OpenAI")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
            }

            Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Group {
            if recorder.isRecording || recorder.lastRecordingURL == nil && !tm.isTranscribing && tm.transcript == nil {
                Button(action: {
                    Task {
                        if recorder.isRecording {
                            await recorder.stopRecording()
                        } else {
                            await recorder.startRecording()
                        }
                        delegate?.updateStatusIcon(isRecording: recorder.isRecording)
                    }
                }) {
                    HStack {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                        Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .accentColor)
            }
        }
    }

    // MARK: - Helpers

    private func levelMeter(label: String, level: Float) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level > 0.5 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(min(level * 4, 1.0)))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

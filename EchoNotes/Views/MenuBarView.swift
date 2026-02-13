import SwiftUI

/// The entire UI — a simple start/stop button with duration and level meters.
struct MenuBarView: View {
    @ObservedObject var recorder: RecordingEngine
    weak var delegate: AppDelegate?

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
            }

            Divider()

            if recorder.isRecording {
                // Recording state
                VStack(spacing: 12) {
                    Text(formatDuration(recorder.duration))
                        .font(.system(size: 36, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Level meters
                    HStack(spacing: 16) {
                        levelMeter(label: "System", level: recorder.systemLevel)
                        levelMeter(label: "Mic", level: recorder.micLevel)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                // Idle state
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
                }
                .frame(maxHeight: .infinity)
            }

            // Error message
            if let error = recorder.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Record / Stop button
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
        .frame(width: 320, height: 280)
    }

    private func levelMeter(label: String, level: Float) -> some View {
        VStack(spacing: 4) {
            // Simple bar
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

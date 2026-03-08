import SwiftUI

/// Primary recording control button (start/stop) with pause/resume controls.
struct RecordingControlsView: View {
    @ObservedObject var recorder: RecordingEngine

    var body: some View {
        Group {
            if shouldShowPrimaryButton {
                if recorder.isRecording {
                    // Show pause/resume/stop controls during recording
                    recordingControls
                } else {
                    // Show start button when not recording
                    startButton
                }
            }
        }
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            if recorder.isPaused {
                // Resume button
                Button(action: {
                    Task {
                        await recorder.resume()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                // Pause button
                Button(action: {
                    Task {
                        await recorder.pause()
                    }
                }) {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)

                // Stop button
                Button(action: {
                    Task {
                        await recorder.stopRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private var startButton: some View {
        Button(action: {
            Task {
                await recorder.startRecording()
            }
        }) {
            HStack {
                Image(systemName: "record.circle")
                Text("Start Recording")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
    }

    private var shouldShowPrimaryButton: Bool {
        recorder.isRecording ||
        (recorder.lastRecordingURL == nil &&
         !recorder.transcriptionManager.isTranscribing &&
         recorder.transcriptionManager.transcript == nil)
    }
}

import SwiftUI

/// Primary recording control button (start/stop).
struct RecordingControlsView: View {
    @ObservedObject var recorder: RecordingEngine

    var body: some View {
        Group {
            if shouldShowPrimaryButton {
                Button(action: {
                    Task {
                        if recorder.isRecording {
                            await recorder.stopRecording()
                        } else {
                            await recorder.startRecording()
                        }
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

    private var shouldShowPrimaryButton: Bool {
        recorder.isRecording ||
        (recorder.lastRecordingURL == nil &&
         !recorder.transcriptionManager.isTranscribing &&
         recorder.transcriptionManager.transcript == nil)
    }
}

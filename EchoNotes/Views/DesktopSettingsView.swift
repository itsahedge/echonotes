import SwiftUI

/// macOS Settings window with tabs for General, AI, and About.
struct DesktopSettingsView: View {
    @EnvironmentObject var recorder: RecordingEngine
    @EnvironmentObject var tm: TranscriptionManager
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Transcription") {
                Picker("Mode", selection: $recorder.transcriptionModeRaw) {
                    ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if recorder.transcriptionMode == .postRecording {
                    Toggle("Auto-transcribe after recording", isOn: $recorder.autoTranscribe)
                }
            }

            Section("Whisper Model") {
                Picker("Model", selection: $tm.selectedModel) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - AI

    private var aiTab: some View {
        SettingsView(tm: tm, onBack: {})
            .padding()
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("EchoNotes")
                .font(.title2.bold())
            Text("Local-first meeting recorder with on-device transcription via WhisperKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

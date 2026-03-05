import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var tm: TranscriptionManager
    @ObservedObject var recorder: RecordingEngine
    
    var body: some View {
        Form {
            Section("Recording") {
                Picker("Transcription Mode", selection: $recorder.transcriptionModeRaw) {
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
            
            Section("Audio") {
                Picker("Microphone", selection: $recorder.selectedSourceId) {
                    Text("System Default").tag("")
                    ForEach(recorder.availableSources, id: \.self) { source in
                        Text(source).tag(source)
                    }
                }
                
                Picker("System Audio Source", selection: $recorder.selectedSystemSourceId) {
                    Text("Disabled").tag("")
                    ForEach(recorder.availableSystemSources, id: \.self) { source in
                        Text(source).tag(source)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            
            Text("EchoNotes")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            Text("Local-first meeting recorder with on-device transcription via WhisperKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Spacer()
            
            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/anomalyco/echonotes")!)
                Link("Privacy Policy", destination: URL(string: "https://echonotes.ai/privacy")!)
            }
            .font(.body)
            .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
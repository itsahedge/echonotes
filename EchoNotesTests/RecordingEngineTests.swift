import Testing
import Foundation
@testable import EchoNotes

@Suite("RecordingEngine State Transitions")
@MainActor
struct RecordingEngineTests {
    @Test("Initial state is not recording")
    func initialState() {
        let engine = RecordingEngine()
        
        #expect(engine.isRecording == false)
        #expect(engine.duration == 0)
        #expect(engine.micLevel == 0)
        #expect(engine.systemLevel == 0)
        #expect(engine.errorMessage == nil)
        #expect(engine.lastRecordingURL == nil)
    }
    
    @Test("Save directory is created in Documents/EchoNotes")
    func saveDirectory() {
        let engine = RecordingEngine()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let expected = docs.appendingPathComponent("EchoNotes", isDirectory: true)
        
        #expect(engine.saveDirectory == expected)
    }
    
    @Test("Transcription mode defaults to post-recording")
    func defaultTranscriptionMode() {
        let engine = RecordingEngine()
        
        #expect(engine.transcriptionMode == .postRecording)
    }
    
    @Test("Auto-transcribe defaults to false")
    func defaultAutoTranscribe() {
        let engine = RecordingEngine()
        
        #expect(engine.autoTranscribe == false)
    }
}

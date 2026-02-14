import Testing
import AVFoundation
@testable import EchoNotes

@Suite("AudioFileWriter")
struct AudioFileWriterTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func makeBuffer(samples: [Float], source: TimestampedBuffer.AudioSource) -> TimestampedBuffer {
        TimestampedBuffer(samples: samples, source: source)
    }

    @Test("Creates output file with audio data")
    func writerCreatesFile() throws {
        let url = tempDir.appendingPathComponent("test.m4a")
        let writer = try AudioFileWriter(outputURL: url, sampleRate: 48000, channels: 2)

        let sys = [Float](repeating: 0.5, count: 4800)
        let mic = [Float](repeating: 0.3, count: 4800)

        writer.writeSystemBuffer(makeBuffer(samples: sys, source: .system))
        writer.writeMicBuffer(makeBuffer(samples: mic, source: .microphone))
        writer.finalize()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as! Int
        #expect(size > 0, "Output file should not be empty")
    }

    @Test("Handles uneven buffer sizes by padding")
    func unevenBuffers() throws {
        let url = tempDir.appendingPathComponent("uneven.m4a")
        let writer = try AudioFileWriter(outputURL: url, sampleRate: 48000, channels: 2)

        writer.writeSystemBuffer(makeBuffer(samples: [Float](repeating: 0.5, count: 9600), source: .system))
        writer.writeMicBuffer(makeBuffer(samples: [Float](repeating: 0.3, count: 4800), source: .microphone))
        writer.finalize()

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Handles empty recording gracefully")
    func emptyRecording() throws {
        let url = tempDir.appendingPathComponent("empty.m4a")
        let writer = try AudioFileWriter(outputURL: url, sampleRate: 48000, channels: 2)
        writer.finalize()

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Multiple buffer flushes produce substantial file")
    func multipleFlushes() throws {
        let url = tempDir.appendingPathComponent("multi.m4a")
        let writer = try AudioFileWriter(outputURL: url, sampleRate: 48000, channels: 2)

        for _ in 0..<10 {
            let sys = (0..<4096).map { _ in Float.random(in: -1...1) }
            let mic = (0..<4096).map { _ in Float.random(in: -1...1) }
            writer.writeSystemBuffer(makeBuffer(samples: sys, source: .system))
            writer.writeMicBuffer(makeBuffer(samples: mic, source: .microphone))
        }
        writer.finalize()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as! Int
        #expect(size > 1000, "Multi-flush recording should produce substantial file")
    }
}

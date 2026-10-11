import Foundation
import AVFoundation
import Testing
@testable import SermonSetCore

// AVFAudio's block type erases sendability. Emulate its off-actor invocation,
// including when the callback was created on the main actor.
private struct FrameworkTap: @unchecked Sendable {
    let call: AVAudioNodeTapBlock
}

@MainActor @Suite(.serialized) struct CallbackIsolationTests {
    @Test(arguments: [48_000.0, 44_100.0])
    func liveTapWritesFromBackgroundQueue(sampleRate: Double) async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try CaptureJournal(directory: root, manifest: CaptureManifest(draft: CaptureDraft(title: "Background tap")))
        let writer = SegmentWriter(journal: journal, onFailure: { @Sendable message in Issue.record(Comment(rawValue: message)) })
        let tap = FrameworkTap(call: LiveCaptureEngine.makeTap(writer: writer))
        let expectedDuration = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, any Error>) in
            DispatchQueue(label: "SermonSetTests.audio-tap").async {
                do {
                    #expect(!Thread.isMainThread)
                    // Stereo 44.1 kHz drives the production converter input block;
                    // mono 48 kHz covers the direct append path.
                    let channels: AVAudioChannelCount = sampleRate == 48_000 ? 1 : 2
                    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false))
                    let frames = AVAudioFrameCount(sampleRate / 5)
                    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
                    buffer.frameLength = frames
                    let samples = try #require(buffer.floatChannelData)
                    for channel in 0..<Int(channels) {
                        for frame in 0..<Int(frames) {
                            samples[channel][frame] = Float(0.05 * sin(2 * .pi * 220 * Double(frame) / sampleRate))
                        }
                    }
                    tap.call(buffer, AVAudioTime(sampleTime: 0, atRate: sampleRate))
                    // AVFAudio can reuse its buffer immediately after the tap returns.
                    // A second silent buffer also verifies we enqueue a copy.
                    for channel in 0..<Int(channels) { samples[channel].update(repeating: 0, count: Int(frames)) }
                    tap.call(buffer, AVAudioTime(sampleTime: Int64(frames), atRate: sampleRate))
                    try writer.flush()
                    continuation.resume(returning: 2 * Double(frames) / sampleRate)
                } catch { continuation.resume(throwing: error) }
            }
        }
        let segment = try #require(CaptureJournal.load(root).manifest.segments.first)
        // Resampling retains the existing converter latency (about 12 ms here).
        let tolerance = sampleRate == AudioFiles.sampleRate ? 1 / AudioFiles.sampleRate : 0.025
        #expect(abs(segment.duration - expectedDuration) < tolerance)
        #expect(abs(writer.snapshot().0 - expectedDuration) < tolerance)
        let url = root.appendingPathComponent(segment.filename)
        #expect(try LocalFiles.checksum(url) == segment.checksumSHA256)
        let audio = try AVAudioFile(forReading: url)
        let decoded = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: decoded)
        let samples = try #require(decoded.floatChannelData?[0])
        #expect((0..<Int(decoded.frameLength)).contains { abs(samples[$0]) > 0.001 })
    }
}

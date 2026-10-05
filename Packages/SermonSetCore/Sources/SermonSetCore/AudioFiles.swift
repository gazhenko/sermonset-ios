import Foundation
import AVFoundation

struct AudioFileInfo: Sendable {
    var duration: TimeInterval
    var byteCount: Int64
    var checksum: String
}

enum AudioFiles {
    static let sampleRate = 48_000.0
    static let bitrate = 96_000
    static var aacSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitrate]
    }
    static func probe(_ url: URL) throws -> AudioFileInfo {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw SermonSetError(title: "Audio could not be read", message: "The file does not contain playable audio.") }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return AudioFileInfo(duration: duration, byteCount: size, checksum: try LocalFiles.checksum(url))
    }
    @concurrent static func inspect(_ url: URL) async throws -> AudioFileInfo { try probe(url) }

    @concurrent static func concatenate(_ inputs: [URL], to destination: URL) async throws -> AudioFileInfo {
        guard !inputs.isEmpty else { throw SermonSetError(title: "No audio to recover", message: "This session has no completed audio segments. The files have been preserved.") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).partial.m4a")
        do {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
            var output: AVAudioFile? = try AVAudioFile(forWriting: temporary, settings: aacSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            for url in inputs {
                try Task.checkCancellation()
                let source = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                guard source.processingFormat.sampleRate == sampleRate, source.processingFormat.channelCount == 1 else { throw SermonSetError(title: "Recording format unavailable", message: "A recording segment has an unexpected format. Its files have been preserved.") }
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
                while source.framePosition < source.length {
                    try Task.checkCancellation()
                    try source.read(into: buffer)
                    if buffer.frameLength > 0 { try output!.write(from: buffer) }
                }
            }
            output = nil // Close the AAC container before checksum, probe, and atomic rename.
            try LocalFiles.protect(temporary)
            let info = try probe(temporary)
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw SermonSetError(title: "Original already exists", message: "The existing original audio was preserved.") }
            try FileManager.default.moveItem(at: temporary, to: destination)
            return info
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

extension SermonStore {
    public func importAudio(from url: URL, title: String?) async throws -> Sermon {
        guard !writesBlocked else { throw report(SermonSetError(title: "Library is protected", message: "Restore or erase the unreadable library before importing audio.")) }
        let securityScoped = url.startAccessingSecurityScopedResource()
        defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
        let id = UUID(), audioID = UUID()
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
        guard ext.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil else { throw report(SermonSetError(title: "Audio could not be imported", message: "Choose a supported local audio file.")) }
        let destination = recordingsDirectory.appendingPathComponent("\(audioID.uuidString).\(ext)")
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard LocalFiles.freeBytes(recordingsDirectory) > size + 5_000_000 else { throw SermonSetError(title: "Storage is low", message: "Free some storage before importing this recording.") }
            try FileManager.default.copyItem(at: url, to: destination)
            try LocalFiles.protect(destination)
            let info = try await AudioFiles.inspect(destination)
            try Task.checkCancellation()
            let audio = AudioAsset(id: audioID, sermonID: id, kind: .imported, duration: info.duration, byteCount: info.byteCount, checksumSHA256: info.checksum)
            let sermon = Sermon(id: id, title: title ?? "", canonicalAudioAssetID: audioID)
            try transaction { state in
                state.sermons[id] = sermon; state.audio[audioID] = audio; state.audioPaths[audioID] = destination.lastPathComponent
                state.history[id] = UserSermonHistory(sermonID: id, source: .imported)
            }
            return sermon
        } catch { try? FileManager.default.removeItem(at: destination); throw report(error) }
    }
}

import Foundation
import AVFoundation

public enum CaptureEngineKind: String, Codable, Hashable, Sendable {
    case live, simulated
    public static func fromLaunchArguments() -> CaptureEngineKind {
        fromLaunchArguments(ProcessInfo.processInfo.arguments)
    }
    static func fromLaunchArguments(_ args: [String]) -> CaptureEngineKind {
        args.contains("-SermonSetSimulatedCapture") ? .simulated : .live
    }
}

@MainActor protocol CaptureAudioEngine: AnyObject {
    var duration: TimeInterval { get }
    var level: Float { get }
    func start(journal: CaptureJournal, onFailure: @escaping @Sendable (String) -> Void) throws
    func pause() throws
    func resume() throws
    func stop() throws
}

/// Owns AVAudioFile only on a dedicated serial queue. Tap callbacks copy buffers
/// and enqueue them; codec/file I/O never runs on the microphone render thread.
final class SegmentWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gazhenko.sermonset.segment-writer", qos: .userInitiated)
    private let journal: CaptureJournal
    private let segmentDuration: Double
    private var file: AVAudioFile?
    private var url: URL?
    private var segmentFrames: Int64 = 0
    private var totalFrames: Int64
    private var rms: Float = 0
    private var failure: String?
    private var converter: AVAudioConverter?
    private let onFailure: @Sendable (String) -> Void
    private var pendingBuffers = 0
    private let backlogLock = NSLock()

    init(journal: CaptureJournal, segmentDuration: Double = 30, onFailure: @escaping @Sendable (String) -> Void) {
        self.journal = journal; self.segmentDuration = segmentDuration; self.onFailure = onFailure
        totalFrames = Int64(journal.manifest.duration * AudioFiles.sampleRate)
    }
    func snapshot() -> (Double, Float) { queue.sync { (Double(totalFrames) / AudioFiles.sampleRate, rms) } }
    func append(_ input: AVAudioPCMBuffer) {
        // Bound memory if the disk/encoder cannot keep up. Preserve prior segments and stop visibly.
        let accepted = backlogLock.withLock { pendingBuffers += 1; return pendingBuffers <= 128 }
        guard accepted else {
            backlogLock.withLock { pendingBuffers -= 1 }
            queue.async { self.fail("Audio could not be written fast enough. Completed segments are preserved.") }
            return
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
            backlogLock.withLock { pendingBuffers -= 1 }; return
        }
        copy.frameLength = input.frameLength
        let src = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<min(src.count, dst.count) {
            if let source = src[i].mData, let target = dst[i].mData { memcpy(target, source, Int(min(src[i].mDataByteSize, dst[i].mDataByteSize))) }
        }
        let box = AudioBufferBox(copy)
        queue.async {
            defer { self.backlogLock.withLock { self.pendingBuffers -= 1 } }
            guard self.failure == nil else { return }
            do { try self.write(box.buffer) } catch { self.fail(error.localizedDescription) }
        }
    }
    private func fail(_ message: String) {
        guard failure == nil else { return }
        failure = message; onFailure(message)
    }
    private func write(_ input: AVAudioPCMBuffer) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFiles.sampleRate, channels: 1, interleaved: false)!
        let output: AVAudioPCMBuffer
        if input.format == format { output = input }
        else {
            if converter == nil || converter!.inputFormat != input.format { converter = AVAudioConverter(from: input.format, to: format) }
            guard let converter else { throw SermonSetError(title: "Input unavailable", message: "The microphone format could not be converted.") }
            let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 128
            output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            let feed = ConverterInputFeed(input)
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, status in
                feed.next(status: status)
            }
            if let conversionError { throw conversionError }
            guard status != .error else { throw SermonSetError(title: "Input unavailable", message: "The microphone audio could not be converted.") }
        }
        guard output.frameLength > 0 else { return }
        if file == nil {
            guard LocalFiles.freeBytes(journal.directory) > 5_000_000 else { throw SermonSetError(title: "Storage is low", message: "Recording paused to protect completed segments. Free some storage to continue.") }
            let newURL = journal.directory.appendingPathComponent("segment-\(UUID().uuidString).m4a")
            file = try AVAudioFile(forWriting: newURL, settings: AudioFiles.aacSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try LocalFiles.protect(newURL); url = newURL
        }
        try file!.write(from: output)
        segmentFrames += Int64(output.frameLength); totalFrames += Int64(output.frameLength)
        if let samples = output.floatChannelData?[0] {
            var squares: Float = 0
            for i in 0..<Int(output.frameLength) { squares += samples[i] * samples[i] }
            rms = min(1, max(0, sqrt(squares / Float(output.frameLength)) * 5))
        }
        if Double(segmentFrames) / AudioFiles.sampleRate >= segmentDuration { try closeSegment() }
    }
    private func closeSegment() throws {
        file = nil // Finish the container before making it recoverable.
        guard let url, segmentFrames > 0 else { return }
        let checksum = try LocalFiles.checksum(url)
        let segment = CaptureSegment(filename: url.lastPathComponent, duration: Double(segmentFrames) / AudioFiles.sampleRate, checksumSHA256: checksum)
        try journal.update { $0.segments.append(segment) }
        self.url = nil; segmentFrames = 0
    }
    func flush() throws {
        try queue.sync {
            try closeSegment()
            if let failure { throw SermonSetError(title: "Recording interrupted", message: failure) }
            rms = 0
        }
    }
}
private final class ConverterInputFeed: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.withLock {
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
    }
}
private final class AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

@MainActor final class LiveCaptureEngine: CaptureAudioEngine {
    private var engine: AVAudioEngine?
    private var writer: SegmentWriter?
    var duration: Double { writer?.snapshot().0 ?? 0 }
    var level: Float { writer?.snapshot().1 ?? 0 }
    func start(journal: CaptureJournal, onFailure: @escaping @Sendable (String) -> Void) throws {
        writer = SegmentWriter(journal: journal, onFailure: onFailure)
        try resume()
    }
    func resume() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // HFP provides Bluetooth input. A2DP is an output profile; never assume it supplies microphone input.
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setPreferredSampleRate(AudioFiles.sampleRate)
        try session.setActive(true)
        #endif
        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0, let writer else { throw SermonSetError(title: "Microphone unavailable", message: "A recording input could not be opened.") }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [writer] buffer, _ in writer.append(buffer) }
        audioEngine.prepare()
        do { try audioEngine.start(); engine = audioEngine }
        catch { input.removeTap(onBus: 0); throw error }
    }
    func pause() throws {
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        engine = nil
        try writer?.flush()
    }
    func stop() throws { try pause() }
}

@MainActor final class SimulatedCaptureEngine: CaptureAudioEngine {
    private var writer: SegmentWriter?
    private var task: Task<Void, Never>?
    private var frameCursor: Int64 = 0
    var duration: Double { writer?.snapshot().0 ?? 0 }
    var level: Float { writer?.snapshot().1 ?? 0 }
    func start(journal: CaptureJournal, onFailure: @escaping @Sendable (String) -> Void) throws {
        writer = SegmentWriter(journal: journal, segmentDuration: 1, onFailure: onFailure)
        try resume()
    }
    func resume() throws {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                if self == nil { return }
            }
        }
    }
    private func tick() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFiles.sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        let data = buffer.floatChannelData![0]
        for i in 0..<4800 {
            let t = Double(frameCursor + Int64(i)) / AudioFiles.sampleRate
            let envelope = 0.04 + 0.035 * (sin(t * 2.3) + 1) / 2
            data[i] = Float(envelope * sin(2 * .pi * 220 * t) + 0.007 * sin(2 * .pi * 329 * t))
        }
        frameCursor += 4800; writer?.append(buffer)
    }
    func pause() throws { task?.cancel(); task = nil; try writer?.flush() }
    func stop() throws { try pause() }
    isolated deinit { task?.cancel() }
}

@MainActor enum AudioSessionCoordinator {
    static var captureOwner: UUID?
    static var playbackPauseHandlers: [UUID: @MainActor () -> Void] = [:]
    static var removalHandlers: [UUID: @MainActor (URL, UUID?) -> Void] = [:]
    static func libraryDidRemove(root: URL, sermonID: UUID?) {
        for handler in Array(removalHandlers.values) { handler(root, sermonID) }
    }
    static let captureBegan = Notification.Name("SermonSetCaptureBegan")
    static func beginCapture(_ id: UUID) throws {
        guard captureOwner == nil || captureOwner == id else { throw SermonSetError(title: "Recording already active", message: "Finish the current recording before starting another.") }
        captureOwner = id
        for pause in Array(playbackPauseHandlers.values) { pause() }
        NotificationCenter.default.post(name: captureBegan, object: nil)
    }
    static func endCapture(_ id: UUID) {
        guard captureOwner == id else { return }
        captureOwner = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

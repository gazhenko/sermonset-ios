import Foundation
import AVFoundation
import Observation

public enum AudioAlignment: Codable, Hashable, Sendable { case original, offset(seconds: Double), unavailable }

public struct AudioTrimWindow: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var duration: TimeInterval { end - start }
    public init(start: TimeInterval, end: TimeInterval) { self.start = start; self.end = end }
    public func validate(duration: TimeInterval) throws {
        guard duration.isFinite, duration > 0, start.isFinite, end.isFinite, start >= 0, start < duration, end > start, end <= duration + 0.1 else {
            throw SermonSetError(title: "Trim needs review", message: "Choose start and end times within the original recording.")
        }
    }
}
public struct MusicSection: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
}
public struct VoiceFocusDiagnostics: Codable, Hashable, Sendable {
    public var clippingPercent: Double
    public var dropoutSeconds: Double
    public var appliedGainDB: Double
    public var inputLUFS: Double?
    public var outputLUFS: Double?
    public var peakDBFS: Double
    public var musicSections: [MusicSection]
}
public struct AudioDerivativeProvenance: Codable, Hashable, Sendable {
    public var sourceAssetID: UUID
    public var sourceChecksum: String
    public var trim: AudioTrimWindow
    public var strength: Double
    public var processMusic: Bool
    public var algorithm: String
    public var diagnostics: VoiceFocusDiagnostics
}
struct CoreFeatures: Codable, Sendable {
    var officialSources: [UUID:OfficialSourceAuthorization]?
    var blockedAccountIDs: [String]?
    var serviceTokens: [UUID:String]?
    var publications: [UUID:PublicationJob]?
    var communityEditions: [UUID: CardEdition]?
    var community: CommunityCache?
    var serverKeys: [ServerSigningKey]?
    var trims: [UUID: AudioTrimWindow] = [:]
    var derivatives: [UUID: AudioDerivativeProvenance] = [:]
    var locales: [UUID: String] = [:]
    var staleTakeaways: Set<UUID> = []
    var staleOutline: Set<UUID> = []
}

// RBJ biquads, constant-memory streaming; no alteration of source samples/files.
struct Biquad {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func sample(_ x: Double) -> Double {
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y.isFinite ? y : 0
    }
    static func highPass(rate: Double, hz: Double) -> Self {
        let w = 2 * Double.pi * hz / rate, c = cos(w), alpha = sin(w) / sqrt(2), d = 1 + alpha
        return Self(b0: (1+c)/2/d, b1: -(1+c)/d, b2: (1+c)/2/d, a1: -2*c/d, a2: (1-alpha)/d)
    }
    static func shelf(rate: Double, hz: Double, db: Double) -> Self {
        let a = pow(10, db/40), w = 2 * Double.pi * hz/rate, c = cos(w), s = sin(w), q = s/sqrt(2), t = 2*sqrt(a)*q
        let d = (a+1)-(a-1)*c+t
        return Self(b0: a*((a+1)+(a-1)*c+t)/d, b1: -2*a*((a-1)+(a+1)*c)/d, b2: a*((a+1)+(a-1)*c-t)/d, a1: 2*((a-1)-(a+1)*c)/d, a2: ((a+1)-(a-1)*c-t)/d)
    }
}
struct SpeechDSP {
    var highPass: Biquad
    var presence: Biquad
    var envelope = 0.0
    let strength: Double
    let release: Double
    init(rate: Double, strength: Double) {
        self.strength = strength
        highPass = .highPass(rate: rate, hz: 80)
        presence = .shelf(rate: rate, hz: 2200, db: 2.5 * strength)
        release = exp(-1 / (rate * 0.08))
    }
    mutating func process(_ input: Float, bypass: Bool) -> Float {
        let x = input.isFinite ? Double(input) : 0
        let filtered = presence.sample(highPass.sample(x))
        envelope = max(abs(filtered), envelope * release)
        let db = 20 * log10(max(envelope, 1e-9))
        let gate = db < -48 ? pow(10, (db+48) * 0.4 * strength/20) : 1
        let compression = db > -18 ? pow(10, -(db+18) * 0.45 * strength/20) : 1
        if bypass || strength == 0 { return Float(x) }
        let wet = filtered * gate * compression
        return Float(x * (1-strength) + wet * strength)
    }
    static func limited(_ samples: [Float], gain: Double) -> [Float] {
        // A conservative ceiling plus four-times cubic-interpolated intersample peak bounds.
        let scaled = samples.map { Double($0.isFinite ? $0 : 0) * gain }
        var peak = scaled.map(abs).max() ?? 0
        if scaled.count > 3 {
            for i in 1..<(scaled.count-2) {
                let a = scaled[i-1], b = scaled[i], c = scaled[i+1], d = scaled[i+2]
                for t in [0.25, 0.5, 0.75] {
                    let y = b + 0.5*t*(c-a+t*(2*a-5*b+4*c-d+t*(3*(b-c)+d-a)))
                    peak = max(peak, abs(y))
                }
            }
        }
        let reduction = peak > 0.89 ? 0.89/peak : 1
        return scaled.map { Float(max(-0.89, min(0.89, $0 * reduction))) }
    }
}
struct LoudnessMeter {
    var hp: Biquad, shelf: Biquad
    var sum = 0.0, count = 0
    var blocks: [Double] = []
    let blockFrames: Int
    init(rate: Double) {
        hp = .highPass(rate: rate, hz: 38)
        shelf = .shelf(rate: rate, hz: 1500, db: 4)
        blockFrames = max(1, Int(rate * 0.4))
    }
    mutating func add(_ sample: Float) {
        let y = hp.sample(shelf.sample(Double(sample)))
        sum += y*y; count += 1
        if count == blockFrames { blocks.append(sum/Double(count)); sum = 0; count = 0 }
    }
    var lufs: Double? {
        let all = blocks + (count > 0 ? [sum/Double(count)] : [])
        let absolute = all.filter { -0.691 + 10*log10(max($0, 1e-15)) > -70 }
        guard !absolute.isEmpty else { return nil }
        let average = absolute.reduce(0,+)/Double(absolute.count)
        let gated = absolute.filter { $0 > average * 0.1 }
        return -0.691 + 10*log10(gated.reduce(0,+)/Double(max(1,gated.count)))
    }
}
enum VoiceFocusRenderer {
    // Spectral flatness + sustained harmonic energy: deliberately a suggestion, not a rights verdict.
    static func likelyMusic(_ samples: [Float], rate: Double) -> Bool {
        guard samples.count >= 512 else { return false }
        let n = 512, stride = max(1, samples.count/n)
        var energies: [Double] = []
        for bin in 2..<64 {
            let coefficient = 2*cos(2*Double.pi*Double(bin)/Double(n))
            var a = 0.0, b = 0.0
            for i in 0..<n {
                let x = Double(samples[min(samples.count-1,i*stride)]) * (0.5-0.5*cos(2*Double.pi*Double(i)/Double(n-1)))
                let next = x + coefficient*a-b; b = a; a = next
            }
            energies.append(max(1e-12,a*a+b*b-coefficient*a*b))
        }
        let total = energies.reduce(0,+), mean = total/Double(energies.count)
        let flatness = exp(energies.map(log).reduce(0,+)/Double(energies.count))/mean
        let tonal = energies.sorted(by: >).prefix(3).reduce(0,+)/total
        let rms = sqrt(samples.reduce(0) { $0+Double($1*$1) }/Double(samples.count))
        return rms > 0.015 && (flatness > 0.65 || tonal > 0.65)
    }
    @concurrent static func render(source: URL, destination: URL, trim: AudioTrimWindow, strength: Double, processMusic: Bool) async throws -> (AudioFileInfo, VoiceFocusDiagnostics) {
        let sourceHash = try LocalFiles.checksum(source)
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = input.processingFormat.sampleRate
        try trim.validate(duration: Double(input.length)/rate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let effectiveEnd = min(trim.end, Double(input.length)/rate)
        let frames = AVAudioFramePosition((effectiveEnd-trim.start)*rate), start = AVAudioFramePosition(trim.start*rate)
        let intermediate = destination.deletingLastPathComponent().appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: intermediate) }
        var music: [MusicSection] = [], previous = false, runStart = 0.0, runCount = 0
        var clipped = 0, silentFrames = 0, totalFrames = 0
        let capacity = AVAudioFrameCount(max(512, Int(rate*0.4)))
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity)!
        input.framePosition = start
        while input.framePosition < start+frames {
            try Task.checkCancellation()
            let offset = Double(input.framePosition-start)/rate
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(capacity),start+frames-input.framePosition)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            let mono = (0..<Int(buffer.frameLength)).map { i in
                (0..<Int(input.processingFormat.channelCount)).reduce(Float(0)) { $0+channels[$1][i] }/Float(input.processingFormat.channelCount)
            }
            clipped += mono.filter { abs($0) >= 0.999 }.count
            let silent = mono.allSatisfy { abs($0) < 0.00001 }
            if silent { silentFrames += mono.count }
            totalFrames += mono.count
            let candidate = likelyMusic(mono, rate: rate)
            if candidate {
                if !previous { runStart = offset; runCount = 0 }
                runCount += 1
            } else if previous && runCount >= 3 { music.append(MusicSection(start: runStart+trim.start, end: offset+trim.start)) }
            previous = candidate
        }
        if previous && runCount >= 3 { music.append(MusicSection(start: runStart+trim.start, end: trim.end)) }
        input.framePosition = start
        var output: AVAudioFile? = try AVAudioFile(forWriting: intermediate, settings: format.settings)
        var dsp = SpeechDSP(rate: rate, strength: strength), meter = LoudnessMeter(rate: rate), originalMeter = LoudnessMeter(rate: rate)
        let processed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
        while input.framePosition < start+frames {
            try Task.checkCancellation()
            let offset = Double(input.framePosition)/rate
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(capacity),start+frames-input.framePosition)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            processed.frameLength = buffer.frameLength
            for i in 0..<Int(buffer.frameLength) {
                let x = (0..<Int(input.processingFormat.channelCount)).reduce(Float(0)) { $0+channels[$1][i] }/Float(input.processingFormat.channelCount)
                let time = offset+Double(i)/rate
                let bypass = !processMusic && music.contains { time >= $0.start && time < $0.end }
                let y = dsp.process(x, bypass: bypass)
                processed.floatChannelData![0][i] = y; meter.add(y); originalMeter.add(x)
            }
            try output!.write(from: processed)
        }
        output = nil
        let inputLUFS = originalMeter.lufs, preLUFS = meter.lufs
        let gainDB = max(-30,min(18,-16-(preLUFS ?? -16))), gain = pow(10,gainDB/20)
        let pcm = try AVAudioFile(forReading: intermediate)
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcm.processingFormat, frameCapacity: capacity)!
        var settings = AudioFiles.aacSettings; settings[AVSampleRateKey] = rate
        var final: AVAudioFile? = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var finalMeter = LoudnessMeter(rate: rate), peak = 0.0
        while pcm.framePosition < pcm.length {
            try Task.checkCancellation(); try pcm.read(into: pcmBuffer)
            let values = SpeechDSP.limited(Array(UnsafeBufferPointer(start: pcmBuffer.floatChannelData![0], count: Int(pcmBuffer.frameLength))), gain: gain)
            for (i,y) in values.enumerated() { pcmBuffer.floatChannelData![0][i] = y; finalMeter.add(y); peak = max(peak,Double(abs(y))) }
            try final!.write(from: pcmBuffer)
        }
        final = nil; try LocalFiles.protect(destination)
        guard try LocalFiles.checksum(source) == sourceHash else { throw SermonSetError(title: "Original changed", message: "The source audio changed while processing. Retry with the original recording.") }
        return (try AudioFiles.probe(destination), VoiceFocusDiagnostics(clippingPercent: Double(clipped)/Double(max(1,totalFrames))*100, dropoutSeconds: Double(silentFrames)/rate, appliedGainDB: gainDB, inputLUFS: inputLUFS, outputLUFS: finalMeter.lufs, peakDBFS: 20*log10(max(peak,1e-9)), musicSections: music))
    }
}
extension SermonStore {
    public func playableDuration(for asset: AudioAsset) -> TimeInterval {
        guard let url = audioURL(for: asset), let info = try? AudioFiles.probe(url) else { return asset.duration }; return info.duration
    }
    public func trimWindow(for assetID: UUID) -> AudioTrimWindow? { document.features?.trims[assetID] }
    public func derivativeProvenance(for assetID: UUID) -> AudioDerivativeProvenance? { document.features?.derivatives[assetID] }
    public func setTrimWindow(_ window: AudioTrimWindow, for assetID: UUID) throws {
        guard let audio = document.audio[assetID] else { throw report(SermonSetError(title: "Audio unavailable", message: "Save the sermon before trimming its audio.")) }
        let duration = playableDuration(for: audio)
        try window.validate(duration: duration)
        let window = AudioTrimWindow(start: window.start,end: min(window.end,duration))
        try transaction { if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.trims[assetID] = window }
    }
    @discardableResult public func renderVoiceFocus(sermonID: UUID, strength: Double = 0.5, processMusic: Bool = false) async throws -> AudioAsset {
        guard strength.isFinite, (0...1).contains(strength), let source = audioAssets(for: sermonID).first(where: { [.original,.imported,.sample].contains($0.kind) }), let url = audioURL(for: source) else { throw report(SermonSetError(title: "Original unavailable", message: "Choose an original recording and strength from 0 to 100 percent.")) }
        let requested = trimWindow(for: source.id) ?? AudioTrimWindow(start: 0,end: source.duration)
        let duration = playableDuration(for: source)
        try requested.validate(duration: duration)
        let trim = AudioTrimWindow(start: requested.start,end: min(requested.end,duration))
        let id = UUID(), destination = recordingsDirectory.appendingPathComponent("\(id).m4a")
        do {
            let (info, diagnostics) = try await VoiceFocusRenderer.render(source: url,destination: destination,trim: trim,strength: strength,processMusic: processMusic)
            let asset = AudioAsset(id: id,sermonID: sermonID,kind: .enhanced,duration: info.duration,byteCount: info.byteCount,checksumSHA256: info.checksum,sourceAudioAssetID: source.id)
            let provenance = AudioDerivativeProvenance(sourceAssetID: source.id,sourceChecksum: try LocalFiles.checksum(url),trim: trim,strength: strength,processMusic: processMusic,algorithm: "VoiceFocus-v1 / K-weighted gated normalization / 4x peak estimate",diagnostics: diagnostics)
            try transaction {
                guard $0.sermons[sermonID] != nil else { throw CancellationError() }
                $0.audio[id] = asset; $0.audioPaths[id] = destination.lastPathComponent
                if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.derivatives[id] = provenance
            }
            return asset
        } catch { try? FileManager.default.removeItem(at: destination); throw report(error) }
    }
}
@MainActor @Observable public final class VoiceFocusController {
    public private(set) var state: JobState = .idle
    public private(set) var asset: AudioAsset?
    public private(set) var diagnostics: VoiceFocusDiagnostics?
    private let store: SermonStore
    public init(store: SermonStore) { self.store = store }
    public func render(sermonID: UUID,strength: Double = 0.5,processMusic: Bool = false) async {
        if case .running = state { return }; state = .running(progress: nil)
        do { let result = try await store.renderVoiceFocus(sermonID: sermonID,strength: strength,processMusic: processMusic); asset = result; diagnostics = store.derivativeProvenance(for: result.id)?.diagnostics; state = .done }
        catch is CancellationError { state = .idle }
        catch { state = .failed(message: error.localizedDescription) }
    }
}

import Testing
import Foundation
@testable import SermonSetCore

@Suite @MainActor struct VoiceFocusTests {
    @Test func defaultAACTrimUsesPlayableDuration() async throws {
        let store = SermonStore(configuration: .preview)
        let sermon = store.libraryEntries[0].sermon
        let original = try #require(store.audioAssets(for: sermon.id).first)
        try store.transaction { $0.audio[original.id]?.duration += 0.04 } // legacy/container AAC padding claim
        let rendered = try await store.renderVoiceFocus(sermonID: sermon.id,strength: 0.5)
        #expect(rendered.duration <= original.duration+0.1)
        #expect(store.derivativeProvenance(for: rendered.id)?.sourceAssetID == original.id)
    }
    @Test func boundsAndInvalidTrim() throws {
        let input: [Float] = [Float.nan, .infinity, -3, 4, 0.5, -0.5, 1, -1]
        let limited = SpeechDSP.limited(input,gain: 100)
        #expect(limited.allSatisfy { $0.isFinite && abs($0) <= 0.89 })
        #expect(throws: SermonSetError.self) { try AudioTrimWindow(start: 2,end: 1).validate(duration: 5) }
        #expect(throws: SermonSetError.self) { try AudioTrimWindow(start: .nan,end: 1).validate(duration: 5) }
        var dsp = SpeechDSP(rate: 48000,strength: 0)
        #expect(dsp.process(0.25,bypass: false) == 0.25)
    }
    @Test func loudnessAndMusicHeuristicsHaveFiniteBounds() {
        let samples: [Float] = (0..<19200).map { Float(0.1 * sin(2 * Double.pi * 80 * Double($0)/48000)) }
        var meter = LoudnessMeter(rate: 48000)
        samples.forEach { meter.add($0) }
        #expect(meter.lufs?.isFinite == true)
        #expect(VoiceFocusRenderer.likelyMusic(samples,rate: 48000))
        #expect(!VoiceFocusRenderer.likelyMusic(Array(repeating: 0,count: 19200),rate: 48000))
        var silent = LoudnessMeter(rate: 48000); (0..<19200).forEach { _ in silent.add(0) }
        #expect(silent.lufs == nil)
    }
    @Test func derivativePreservesOriginalAndAnchors() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SermonStore(configuration: .uiTest(directory: dir))
        try store.keepSample(store.discoverCatalog[0].id)
        let sermon = store.libraryEntries[0].sermon
        let original = try #require(store.audioAssets(for: sermon.id).first)
        let url = try #require(store.audioURL(for: original)), hash = try LocalFiles.checksum(url)
        let moment = try store.addMoment(sermonID: sermon.id,time: 2,note: "private")
        try store.setTrimWindow(AudioTrimWindow(start: 1,end: 4),for: original.id)
        let enhanced = try await store.renderVoiceFocus(sermonID: sermon.id)
        #expect(enhanced.sourceAudioAssetID == original.id)
        #expect(abs(enhanced.duration-3) < 0.1)
        #expect(try LocalFiles.checksum(url) == hash)
        #expect(store.sermon(sermon.id)?.canonicalAudioAssetID == original.id)
        #expect(store.moments(for: sermon.id) == [moment])
        let provenance = try #require(store.derivativeProvenance(for: enhanced.id))
        #expect(provenance.sourceChecksum == hash)
        #expect(provenance.diagnostics.peakDBFS < 0)
        let player = PlaybackController(store: store)
        player.load(sermonID: sermon.id,autoplay: false); player.seek(to: 2)
        try player.selectAudioAsset(enhanced.id)
        #expect(abs(player.currentTime-2) < 0.05)
        try player.revertToOriginal()
        #expect(player.activeAssetID == original.id)
        let reopened = SermonStore(configuration: .uiTest(directory: dir))
        #expect(reopened.derivativeProvenance(for: enhanced.id) != nil)
    }
}

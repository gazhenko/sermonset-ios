import Foundation

struct SampleCatalog: Sendable {
    var sermons: [Sermon] = []
    var audio: [UUID: AudioAsset] = [:]
    var audioURLs: [UUID: URL] = [:]
    var transcripts: [UUID: Transcript] = [:]
    var insights: [UUID: SermonInsights] = [:]
    var previewMoments: [MarkedMoment] = []
    var previewNotes: [PersonalNote] = []

    struct Document: Decodable { var sermons: [Fixture] }
    struct Fixture: Decodable {
        struct Place: Decodable { var churchName: String?; var city: String?; var region: String?; var country: String?; var latitude: Double?; var longitude: Double?; var precision: LocationPrecision }
        struct Segment: Decodable { var start: Double; var end: Double; var text: String; var confidence: Double }
        struct Chapter: Decodable { var title: String; var segment: Int }
        struct Point: Decodable { var text: String; var segments: [Int] }
        struct Moment: Decodable { var segment: Int; var note: String? }
        var slug: String; var title: String; var preacher: String?; var venue: Place?; var serviceDate: String
        var primaryPassage: String?; var sermonType: SermonType?; var themes: [String]; var summary: String?; var reflectionPrompt: String?
        var trustState: TrustState; var rightsState: RightsState; var segments: [Segment]; var outline: [Chapter]; var takeaways: [Point]; var scriptureReferences: [String]
        var sampleMoments: [Moment]; var sampleNotes: [String]; var duration: Double; var byteCount: Int64; var checksumSHA256: String; var audioFile: String
    }
    static func load() -> SampleCatalog {
        var catalog = SampleCatalog()
        guard let url = Bundle.module.url(forResource: "samples", withExtension: "json"), let data = try? Data(contentsOf: url), let doc = try? JSONDecoder().decode(Document.self, from: data) else { return catalog }
        for fixture in doc.sermons {
            let id = LocalFiles.stableUUID("sample:\(fixture.slug)")
            let audioID = LocalFiles.stableUUID("sample-audio:\(fixture.slug)")
            let date = ISO8601DateFormatter().date(from: fixture.serviceDate + "T12:00:00Z") ?? .distantPast
            let venue = fixture.venue.map { Venue(id: LocalFiles.stableUUID("venue:\(fixture.slug)"), churchName: $0.churchName, city: $0.city, region: $0.region, country: $0.country, latitude: $0.latitude, longitude: $0.longitude, precision: $0.precision) }
            let audio = AudioAsset(id: audioID, sermonID: id, kind: .sample, duration: fixture.duration, byteCount: fixture.byteCount, createdAt: date, checksumSHA256: fixture.checksumSHA256)
            let sermon = Sermon(id: id, title: fixture.title, preacher: fixture.preacher, venue: venue, serviceDate: date, primaryPassage: fixture.primaryPassage, sermonType: fixture.sermonType, themes: fixture.themes, summary: fixture.summary, reflectionPrompt: fixture.reflectionPrompt, trustState: fixture.trustState, rightsState: fixture.rightsState, isSample: true, canonicalAudioAssetID: audioID, createdAt: date, updatedAt: date)
            let segments = fixture.segments.enumerated().map { index, segment in TranscriptSegment(id: LocalFiles.stableUUID("segment:\(fixture.slug):\(index)"), start: segment.start, end: segment.end, text: segment.text, confidence: segment.confidence) }
            let transcript = Transcript(id: LocalFiles.stableUUID("transcript:\(fixture.slug):1"), sermonID: id, audioAssetID: audioID, segments: segments, engine: "Sample fixture", createdAt: date)
            let points = fixture.takeaways.compactMap { point -> Takeaway? in
                guard let evidence = EvidenceValidator.range(transcript: transcript, indexes: point.segments) else { return nil }
                return Takeaway(text: EvidenceValidator.paraphrase(point.text), evidence: evidence, reviewState: .reviewed, isLowEvidence: EvidenceValidator.isLowEvidence(evidence, transcript: transcript))
            }
            let outline = fixture.outline.compactMap { item -> OutlineItem? in
                guard let evidence = EvidenceValidator.range(transcript: transcript, indexes: [item.segment]) else { return nil }
                return OutlineItem(title: item.title, start: evidence.start, evidence: evidence)
            }
            let file = URL(fileURLWithPath: fixture.audioFile)
            guard file.lastPathComponent == fixture.audioFile, EvidenceValidator.validSegments(segments) else { continue }
            catalog.sermons.append(sermon); catalog.audio[audioID] = audio
            catalog.audioURLs[audioID] = Bundle.module.url(forResource: file.deletingPathExtension().lastPathComponent, withExtension: file.pathExtension)
            catalog.transcripts[id] = transcript
            catalog.insights[id] = SermonInsights(id: LocalFiles.stableUUID("insights:\(fixture.slug)"), sermonID: id, transcriptID: transcript.id, transcriptRevision: 1, generator: "Sample fixture", promptVersion: "fixture-v1", createdAt: date, outline: outline, takeaways: points, scriptureReferences: fixture.scriptureReferences, transcriptChecksumSHA256: EvidenceValidator.contentHash(transcript), generatorRuntime: "Bundled fixture-v1")
            for moment in fixture.sampleMoments where segments.indices.contains(moment.segment) {
                catalog.previewMoments.append(MarkedMoment(sermonID: id, audioAssetID: audioID, time: segments[moment.segment].start, note: moment.note, createdAt: date))
            }
            for text in fixture.sampleNotes { catalog.previewNotes.append(PersonalNote(sermonID: id, audioAssetID: audioID, text: text, createdAt: date, updatedAt: date)) }
        }
        return catalog
    }
}

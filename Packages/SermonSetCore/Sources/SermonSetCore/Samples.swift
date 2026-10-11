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
    static func fixtureSummary(slug: String, bigIdea: String?, reflection: String?, transcript: Transcript) -> SermonSummary? {
        // Hand-written preview content, never a substitute for unavailable inference.
        let sentences: [(String, [Int])]
        switch slug {
        case "peace-in-the-storm": sentences = [
            ("The preacher describes the disciples encountering a storm while following Jesus.", [1, 2, 5]),
            ("Jesus calms the sea and invites the disciples to trust his presence.", [7, 8, 9]),
            ("The preacher encourages naming Jesus before naming fear when difficulties arise.", [10, 11, 12])]
        case "when-faith-gets-loud": sentences = [
            ("The preacher connects worship with everyday actions in response to God's mercy.", [2, 3, 4]),
            ("Renewing the mind changes a person from within rather than following surrounding pressures.", [5, 6, 7, 8]),
            ("Quiet acts of care can make faith visible in daily life.", [9, 10, 11, 12])]
        case "open-hands": sentences = [
            ("The preacher describes Jesus addressing worry among people facing real uncertainty.", [1, 2, 3]),
            ("The birds and lilies illustrate God's care, inviting trust instead of trying to control tomorrow.", [4, 5, 6, 7]),
            ("Seeking God's kingdom first and praying with open hands offer a daily practice of trust.", [8, 9, 10, 11, 12])]
        case "built-in-the-waiting": sentences = [
            ("The preacher observes David moving between confidence and longing in the same psalm.", [0, 1, 2, 3]),
            ("Waiting can become a place where God shapes a person rather than a pause before life begins.", [4, 5, 6, 7]),
            ("The preacher invites patient courage and attention to what God may be forming in the pause.", [8, 9, 10, 12, 13])]
        case "the-table-gets-wider": sentences = [
            ("The preacher recounts Jesus describing invited guests making excuses to miss a banquet.", [1, 3, 4, 5]),
            ("The invitation expands to people outside the original guest list, with room still available.", [6, 7, 9, 10]),
            ("The preacher connects grace with making room for others in everyday gatherings.", [11, 12, 13])]
        case "start-where-you-are": sentences = [
            ("The preacher uses James's example of unmet physical needs to connect faith with action.", [0, 2, 3, 4]),
            ("Living faith moves toward others rather than waiting for an opportunity to solve everything.", [6, 7, 8, 9]),
            ("The preacher encourages beginning with one practical act for the person nearby.", [10, 11, 12, 13])]
        case "songs-in-the-night": sentences = [
            ("The preacher describes Paul and Silas singing in prison before their circumstances change.", [1, 2, 3, 4]),
            ("After the earthquake opens the doors, they stay because the jailer's life matters.", [6, 7, 8, 9]),
            ("The preacher presents worship in difficulty as trust in God before rescue becomes visible.", [10, 11, 12, 13])]
        case "breakfast-on-the-shore": sentences = [
            ("The preacher describes Peter returning to fishing after failure and encountering Jesus on the shore.", [1, 2, 3, 4, 5]),
            ("Jesus welcomes Peter with breakfast and asks about his love at another charcoal fire.", [6, 7, 8, 9]),
            ("The preacher presents restoration as being forgiven and trusted with responsibility again.", [10, 11, 12, 13])]
        default: return nil
        }
        return SermonSummary(bigIdea: bigIdea ?? "", sentences: sentences.map { text, indexes in
            let range = EvidenceValidator.range(transcript: transcript, indexes: indexes)!
            return SummarySentence(id: LocalFiles.stableUUID("summary:\(slug):\(indexes[0])"), text: text, evidence: range, isLowEvidence: EvidenceValidator.isLowEvidence(range, transcript: transcript))
        }, reflectionQuestion: reflection)
    }
    static func fixtureNotes(_ fixture: Fixture, transcript: Transcript) -> SermonNotes? {
        guard let legacy = fixtureSummary(slug: fixture.slug, bigIdea: fixture.summary, reflection: fixture.reflectionPrompt, transcript: transcript) else { return nil }
        // Three hand-written teaching points and exact phrases from the bundled
        // speech fixture. These are preview content, never inference fallbacks.
        let headings: [String], phrases: [(Int, String)], action: String, question: String
        switch fixture.slug {
        case "peace-in-the-storm":
            headings = ["Following Jesus through storms", "Peace in his presence", "Name Jesus before fear"]
            phrases = [(2, "The waves are breaking into the boat."), (7, "Peace. Be still."), (11, "It's remembering who is with you in them.")]
            action = "Name one fear in prayer."; question = "Where do you need peace today?"
        case "when-faith-gets-loud":
            headings = ["Mercy comes first", "Change from within", "Make worship visible"]
            phrases = [(2, "That is your true and proper worship."), (7, "It works from the inside out."), (11, "A transformed life becomes a visible act of worship.")]
            action = "Choose one quiet act of care."; question = "How could your daily actions express worship?"
        case "open-hands":
            headings = ["Bring real worries", "Receive God's care", "Practice open-handed trust"]
            phrases = [(2, "Rent is due on the first."), (7, "The honest answer is no."), (11, "Trust loosens our grip on what tomorrow might bring.")]
            action = "Pray with your hands open."; question = "What are you holding tightly today?"
        case "built-in-the-waiting":
            headings = ["Confidence alongside longing", "The waiting is the room", "Wait with courage"]
            phrases = [(2, "Hear me, Lord, when I call."), (7, "the waiting is often the room."), (10, "Be strong and take heart, and wait for the Lord.")]
            action = "Notice one way waiting is shaping you."; question = "What could God be forming in your waiting?"
        case "the-table-gets-wider":
            headings = ["Hear the invitation", "There is still room", "Make room for others"]
            phrases = [(3, "A man is preparing a great banquet, and he invites many guests."), (7, "And there is still room."), (11, "Grace keeps making room for people we did not expect.")]
            action = "Invite someone you might overlook."; question = "Who could you make room for this week?"
        case "start-where-you-are":
            headings = ["See the unmet need", "Living faith moves", "Take the next faithful action"]
            phrases = [(2, "Can such faith save them?"), (7, "faith by itself, if it is not accompanied by action, is dead."), (11, "I will show you my faith by my deeds.")]
            action = "Help the person in front of you."; question = "What practical need could you meet today?"
        case "songs-in-the-night":
            headings = ["Worship before rescue", "Care beyond the open door", "Trust before the answer"]
            phrases = [(2, "the other prisoners were listening to them."), (7, "He draws his sword."), (11, "The night that began in chains ends at a kitchen table.")]
            action = "Pray or sing in one difficult moment."; question = "How could you practice trust before circumstances change?"
        case "breakfast-on-the-shore":
            headings = ["Return after failure", "Meet Jesus at the fire", "Receive responsibility again"]
            phrases = [(2, "the old life can feel safer."), (7, "Now Jesus has built another one."), (11, "It's being trusted again.")]
            action = "Take one step toward restored responsibility."; question = "Where could you receive a fresh start?"
        default: return nil
        }
        let points = legacy.sentences.enumerated().map { i, sentence in
            let (index, phrase) = phrases[i]
            let evidence = EvidenceValidator.range(transcript: transcript, indexes: [index])!
            return SermonPoint(id: LocalFiles.stableUUID("notes:\(fixture.slug):\(i)"), heading: headings[i], summary: sentence.text, scripture: fixture.scriptureReferences.filter { reference in
                let text = transcript.segments.filter { sentence.evidence!.segmentIDs.contains($0.id) }.map(\.text).joined(separator: " ")
                return NotesValidation.scripture(reference, source: text) != nil
            }, keyPhrase: KeyPhrase(text: phrase, start: transcript.segments[index].start, evidence: evidence), start: sentence.evidence!.start, evidence: sentence.evidence)
        }
        return SermonNotes(title: fixture.title, bigIdea: fixture.summary ?? "", mainPassage: fixture.primaryPassage, points: points, thisWeek: [action], questions: [fixture.reflectionPrompt ?? question, question], engine: "Hand-written sample fixture")
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
            catalog.insights[id] = SermonInsights(id: LocalFiles.stableUUID("insights:\(fixture.slug)"), sermonID: id, transcriptID: transcript.id, transcriptRevision: 1, generator: "Sample fixture", promptVersion: "fixture-v1", createdAt: date, outline: outline, takeaways: points, scriptureReferences: fixture.scriptureReferences, transcriptChecksumSHA256: EvidenceValidator.contentHash(transcript), generatorRuntime: "Bundled fixture-v1", summary: fixtureSummary(slug: fixture.slug, bigIdea: fixture.summary, reflection: fixture.reflectionPrompt, transcript: transcript), notes: fixtureNotes(fixture, transcript: transcript))
            for moment in fixture.sampleMoments where segments.indices.contains(moment.segment) {
                catalog.previewMoments.append(MarkedMoment(sermonID: id, audioAssetID: audioID, time: segments[moment.segment].start, note: moment.note, createdAt: date))
            }
            for text in fixture.sampleNotes { catalog.previewNotes.append(PersonalNote(sermonID: id, audioAssetID: audioID, text: text, createdAt: date, updatedAt: date)) }
        }
        return catalog
    }
}

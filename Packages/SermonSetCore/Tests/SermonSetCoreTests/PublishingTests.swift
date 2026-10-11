import Testing
import Foundation
@testable import SermonSetCore
@MainActor final class FakeUploader: PublicationUploadTransport {
    var onCompletion: (@MainActor @Sendable (UploadCompletion) -> Void)?
    var starts: [UUID] = []
    func start(jobID: UUID,url: URL,file: URL) throws -> Int { starts.append(jobID); return 1 }
    func restore() async -> [UUID:Int] { [:] }
    func cancel(jobID: UUID) {}
}
extension CommunityTests {
    static let reviewed = PublishChecklist(musicReviewed: true,prayerRequestsReviewed: true,childrenReviewed: true,privateTalkReviewed: true)
    @Test func privacyConsentAndAudioGates() async throws {
        let store = SermonStore(configuration: .preview)
        let source = try #require(store.audioURL(for: store.audioAssets(for: store.libraryEntries[0].id)[0]))
        var local = try await store.importAudio(from: source,title: "Private sermon")
        local.preacher = "Test speaker"; local.primaryPassage = "John 1"; local.sermonType = .wisdom; try store.updateSermon(local)
        _ = try store.addNote(sermonID: local.id,text: "never upload this note",time: nil)
        _ = try store.addMoment(sermonID: local.id,time: 1,note: "never upload this moment")
        #expect(throws: SermonSetError.self) { try store.buildPublishRequest(sermonID: local.id,selection: PublishSelection(checklist: PublishChecklist()),audience: "https://test") }
        let payload = try store.buildPublishRequest(sermonID: local.id,selection: PublishSelection(checklist: Self.reviewed),audience: "https://test")
        let json = String(decoding: try APIJSON.encoder.encode(payload),as: UTF8.self)
        for key in ["never upload", "transcripts", "notes", "moments", "latitude", "listeningPosition"] { #expect(!json.contains(key)) }
        #expect(payload.audio == nil)
        let original = try #require(local.canonicalAudioAssetID)
        #expect(throws: SermonSetError.self) { try store.buildPublishRequest(sermonID: local.id,selection: PublishSelection(audioAssetID: original,churchID: "church",rightsBasis: .churchReview,checklist: Self.reviewed),audience: "https://test") }
        try store.setTrimWindow(AudioTrimWindow(start: 0,end: 2),for: original)
        let enhanced = try await store.renderVoiceFocus(sermonID: local.id)
        #expect(throws: SermonSetError.self) { try store.buildPublishRequest(sermonID: local.id,selection: PublishSelection(audioAssetID: enhanced.id,checklist: Self.reviewed),audience: "https://test") }
        let audioPayload = try store.buildPublishRequest(sermonID: local.id,selection: PublishSelection(audioAssetID: enhanced.id,churchID: "church",rightsBasis: .churchReview,checklist: Self.reviewed),audience: "https://test")
        #expect(audioPayload.audio?.sourceChecksumSHA256 == store.document.audio[original]?.checksumSHA256)
        #expect(audioPayload.audio?.duration == enhanced.duration)
    }
    @Test func offlineQueueRetainsConsentAndRetriesSameID() async throws {
        let store = SermonStore(configuration: .preview)
        let source = try #require(store.audioURL(for: store.audioAssets(for: store.libraryEntries[0].id)[0]))
        var local = try await store.importAudio(from: source,title: "Review")
        local.preacher = "Test speaker"; local.primaryPassage = "John 1"; local.sermonType = .wisdom; try store.updateSermon(local)
        let configuration = CommunityConfiguration(baseURL: URL(string: "https://community.test")!)
        StubProtocol.handler = { _ in (200,Data("{\"account\":{\"id\":\"a\",\"displayName\":null,\"avatarStyle\":\"abstract\",\"journeyOptIn\":false,\"journeyCity\":null,\"roles\":[]}}".utf8)) }
        let community = CommunityController(store: store,configuration: configuration,signer: MemoryDeviceIdentity(),session: StubProtocol.session())
        try await community.createAccount()
        let queue = PublishingController(store: store,community: community,uploader: FakeUploader())
        #expect(throws: SermonSetError.self) { try queue.enqueue(sermonID: local.id,selection: PublishSelection(checklist: Self.reviewed),confirmed: false) }
        let job = try queue.enqueue(sermonID: local.id,selection: PublishSelection(checklist: Self.reviewed),confirmed: true)
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }; await queue.process()
        #expect(queue.jobs.first?.id == job.id)
        #expect(queue.jobs.first?.retryAt != nil)
        StubProtocol.handler = { request in
            if request.httpMethod == "POST" { #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == job.id.uuidString); return (200,Data("{\"publicationID\":\"pub\",\"sermonID\":\"s\",\"audioAssetID\":null,\"uploadURL\":null}".utf8)) }
            return (200,Data("{\"publication\":{\"id\":\"pub\",\"sermonID\":\"s\",\"state\":\"published\",\"audioAssetID\":null,\"createdAt\":\"2026-10-05T00:00:00Z\"}}".utf8))
        }
        await queue.retry(job.id)
        #expect(queue.jobs.first?.state == .published)
        let cancelled = try queue.enqueue(sermonID: local.id,selection: PublishSelection(checklist: Self.reviewed),confirmed: true)
        try queue.cancel(cancelled.id); await queue.process()
        #expect(queue.jobs.first(where: { $0.id == cancelled.id })?.isCancelled == true)
        #expect(queue.jobs.first(where: { $0.id == cancelled.id })?.publicationID == nil)
        #expect(store.isInLibrary(local.id))
    }
}

@MainActor @Suite struct PublishRequestTests {
    @Test(arguments: ["title", "preacher", "passage", "kind"])
    func missingPublicDetailNamesOnlyThatField(field: String) throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        var sermon = Sermon(title: "Chosen title",preacher: "Test speaker",primaryPassage: "John 1",sermonType: .wisdom)
        switch field {
        case "title": sermon.title = " \t\n"
        case "preacher": sermon.preacher = nil
        case "passage": sermon.primaryPassage = nil
        case "kind": sermon.sermonType = nil
        default: Issue.record("Unexpected missing field: \(field)")
        }
        try store.transaction { $0.sermons[sermon.id] = sermon }
        do {
            _ = try store.buildPublishRequest(sermonID: sermon.id,selection: PublishSelection(checklist: CommunityTests.reviewed),audience: "https://test")
            Issue.record("Publishing must reject a missing \(field).")
        } catch let error as SermonSetError {
            #expect(error.message == "Add the missing fields before publishing: \(field).")
        }
    }

    @Test(arguments: [nil, "", " \t\n"] as [String?])
    func missingPublicDetailsNamesAllMissingFields(blank: String?) throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let sermon = Sermon(title: blank ?? "",preacher: blank,primaryPassage: blank)
        try store.transaction { $0.sermons[sermon.id] = sermon }
        do {
            _ = try store.buildPublishRequest(sermonID: sermon.id,selection: PublishSelection(checklist: CommunityTests.reviewed),audience: "https://test")
            Issue.record("Publishing must reject missing public details.")
        } catch let error as SermonSetError {
            #expect(error.message == "Add the missing fields before publishing: title, preacher, passage, kind.")
        }
    }

    @Test(arguments: SermonType.allCases)
    func completePublicDetailsPreserveChosenKind(kind: SermonType) throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let sermon = Sermon(title: "Chosen title",preacher: " Test speaker \n",primaryPassage: "\tJohn 1 ",sermonType: kind)
        try store.transaction { $0.sermons[sermon.id] = sermon }
        let payload = try store.buildPublishRequest(sermonID: sermon.id,selection: PublishSelection(checklist: CommunityTests.reviewed),audience: "https://test")
        #expect(payload.title == "Chosen title")
        #expect(payload.preacher == "Test speaker")
        #expect(payload.primaryPassage == "John 1")
        #expect(payload.sermonType == kind.rawValue)
        #expect(store.sermon(sermon.id) == sermon)
    }
}

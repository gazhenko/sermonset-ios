import Foundation
import Testing
@testable import SermonSetCore

@MainActor func testDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SermonSetTests-\(UUID().uuidString)", isDirectory: true) }

@MainActor @Suite struct StoreTests {
    @Test func updatingSermonPersistsServiceDateAndKeepsCreatedAtImmutable() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        let sample = try #require(store.discoverCatalog.first)
        try store.keepSample(sample.id)
        let original = try #require(store.sermon(sample.id)), history = try #require(store.entry(for: sample.id)?.history)
        var edited = original
        edited.serviceDate = original.serviceDate.addingTimeInterval(-7 * 86400)
        edited.createdAt = .distantPast
        try store.updateSermon(edited)
        #expect(store.sermon(original.id)?.serviceDate == edited.serviceDate)
        #expect(store.entry(for: original.id)?.sermon.serviceDate == edited.serviceDate)
        #expect(store.sermon(original.id)?.createdAt == original.createdAt)
        #expect(store.entry(for: original.id)?.history == history)
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        #expect(reopened.sermon(original.id)?.serviceDate == edited.serviceDate)
        #expect(reopened.sermon(original.id)?.createdAt == original.createdAt)
        let reopenedHistory = try #require(reopened.entry(for: original.id)?.history)
        #expect(reopenedHistory.source == history.source)
        // Version 1 persists acquisition dates at whole-second ISO-8601 precision.
        #expect(abs(reopenedHistory.firstEncounteredAt.timeIntervalSince(history.firstEncounteredAt)) < 1)
        #expect(reopened.sermon(original.id)?.canonicalAudioAssetID == original.canonicalAudioAssetID)
    }
    @Test func roundTripRetainsPersonalDataAndCollection() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        #expect(store.libraryEntries.isEmpty)
        let sample = try #require(store.discoverCatalog.first)
        try store.keepSample(sample.id)
        let note = try store.addNote(sermonID: sample.id, text: "Private reflection", time: 12)
        let moment = try store.addMoment(sermonID: sample.id, time: 8, note: "Revisit")
        var updated = sample; updated.title = "My corrected title"; updated.trustState = .churchVerified; updated.canonicalAudioAssetID = nil
        try store.updateSermon(updated)
        store.recordListening(sermonID: sample.id, position: 30, duration: 100)
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        #expect(reopened.lastError == nil)
        #expect(reopened.sermon(sample.id)?.title == "My corrected title")
        #expect(reopened.sermon(sample.id)?.trustState == sample.trustState)
        #expect(reopened.sermon(sample.id)?.canonicalAudioAssetID == sample.canonicalAudioAssetID)
        #expect(reopened.notes(for: sample.id).first?.id == note.id)
        #expect(reopened.moments(for: sample.id).first?.id == moment.id)
        #expect(reopened.entry(for: sample.id)?.history.listeningPosition == 30)
        #expect(reopened.binder.count == 1)
        #expect(reopened.transcript(for: sample.id) != nil)
    }
    @Test func corruptionIsPreservedAndCannotBeOverwritten() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try LocalFiles.createDirectory(root)
        let file = root.appendingPathComponent("store.json"), bytes = Data("{broken private library".utf8)
        try bytes.write(to: file)
        let store = SermonStore(configuration: .uiTest(directory: root))
        #expect(store.lastError != nil)
        store.clearError()
        #expect(throws: SermonSetError.self) { try store.addSampleSermons() }
        #expect(try Data(contentsOf: file) == bytes)
        let preserved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("store-corrupt-") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: preserved[0]) == bytes)
        try store.eraseAllData()
        #expect(store.lastError == nil)
        try store.addSampleSermons()
        #expect(store.libraryEntries.count == 2)
    }
    @Test func unknownSchemaAndInvalidOwnershipArePreserved() throws {
        for version in [1, 999] {
            let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            try LocalFiles.createDirectory(root)
            var doc = StoreDocument(); doc.schemaVersion = version
            if version == 1 {
                let id = UUID(), edition = UUID()
                let card = CardInstance(editionID: edition, sermonID: id, source: .trade)
                doc.cards[card.id] = card
            }
            let file = root.appendingPathComponent("store.json")
            try LocalFiles.write(doc, to: file); let original = try Data(contentsOf: file)
            let store = SermonStore(configuration: .uiTest(directory: root))
            #expect(store.lastError != nil)
            #expect(throws: SermonSetError.self) { try store.addSampleSermons() }
            #expect(try Data(contentsOf: file) == original)
        }
    }
    @Test func keepPackAndCardCreationAreIdempotentAndTradeRetainsEverything() throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let sample = try #require(store.discoverCatalog.first)
        let first = try store.createCard(for: sample.id)
        for _ in 0..<3 { try store.keepSample(sample.id); #expect(try store.createCard(for: sample.id) == first) }
        let pack = store.currentSundayPack(now: Date(timeIntervalSince1970: 1_791_158_400))
        try store.keepPack(pack); let count = store.binder.count
        try store.keepPack(pack); #expect(store.binder.count == count)
        let note = try store.addNote(sermonID: sample.id, text: "Stays private", time: nil)
        let moment = try store.addMoment(sermonID: sample.id, time: 5, note: nil)
        let history = store.entry(for: sample.id)?.history, transcript = store.transcript(for: sample.id), audio = store.audioAssets(for: sample.id)
        try store.previewTrade(cardID: first.id); try store.previewTrade(cardID: first.id)
        #expect(store.card(first.id) == nil)
        #expect(store.entry(for: sample.id)?.ownsCard == false)
        #expect(store.entry(for: sample.id)?.history == history)
        #expect(store.notes(for: sample.id).contains(note))
        #expect(store.moments(for: sample.id).contains(moment))
        #expect(store.transcript(for: sample.id) == transcript)
        #expect(store.audioAssets(for: sample.id) == audio)
        #expect(store.audioURL(for: audio[0]) != nil)
        #expect(store.binder.allSatisfy { store.entry(for: $0.sermonID) != nil })
    }
    @Test func sundayPackIsStableAcrossKeepsAndReloadAndPrefersNewSamples() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try store.addSampleSermons()
        let now = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!
        let pack = store.currentSundayPack(now: now)
        #expect(pack.id == "2026-W41")
        #expect(pack.isDemo && pack.sermons.count == 5)
        #expect(Set(pack.sermons.map(\.id)).count == 5)
        #expect(pack.sermons.allSatisfy { !store.isInLibrary($0.id) })
        try store.keepPack(pack)
        #expect(store.currentSundayPack(now: now).sermons.map(\.id) == pack.sermons.map(\.id))
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        #expect(reopened.currentSundayPack(now: now).sermons.map(\.id) == pack.sermons.map(\.id))
        #expect(reopened.currentSundayPack(now: now.addingTimeInterval(7 * 86400)).id == "2026-W42")
        #expect(store.currentSundayPack(now: ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!).id == "2026-W53")
    }
    @Test func stableEditionSeedDoesNotUseRandomizedHasher() throws {
        let a = SermonStore(configuration: .preview), b = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: a.root); try? FileManager.default.removeItem(at: b.root) }
        let id = try #require(a.discoverCatalog.first?.id)
        #expect(a.edition(for: id)?.designSeed == b.edition(for: id)?.designSeed)
        #expect(a.edition(for: id)?.id == b.edition(for: id)?.id)
    }
    @Test func exportIncludesNotesButNoAudioBytesOrPaths() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        defer { try? FileManager.default.removeItem(at: store.exportsDirectory) }
        try store.addSampleSermons()
        let id = try #require(store.libraryEntries.first?.id)
        try store.addNote(sermonID: id, text: "Private export note", time: nil)
        let url = try store.exportArchive(), data = try Data(contentsOf: url)
        let exported = try LocalFiles.decoder.decode(StoreDocument.self, from: data)
        #expect(exported.notes.values.contains { $0.text == "Private export note" })
        #expect(exported.audioPaths.isEmpty)
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(data.count < 200_000)
        #expect(try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).allSatisfy { $0.pathExtension == "json" })
    }
    @Test func backupFlagAndFileProtectionPersist() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        #expect(store.backupPreference == .deviceBackup)
        try store.setBackupPreference(.excludeFromBackup)
        #expect(try store.recordingsDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(SermonStore(configuration: .uiTest(directory: root)).backupPreference == .excludeFromBackup)
        try store.setBackupPreference(.deviceBackup)
        #expect(try store.recordingsDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
        // Data Protection is not applied by iOS Simulator; verify it on an iPhone.
        #if os(iOS) && !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.storeURL.path)
        #expect((attributes[.protectionKey] as? String) == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #endif
    }
    @Test func updatingMomentEditsOnlyItsNoteAndPersists() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try store.addSampleSermons()
        let id = try #require(store.libraryEntries.first?.id)
        let original = try store.addMoment(sermonID: id, time: 8, note: "First note")
        var edit = original
        edit.note = "Revised reflection"
        edit.time = 99
        edit.audioAssetID = UUID()
        edit.createdAt = .distantPast
        try store.updateMoment(edit)
        var expected = original; expected.note = edit.note
        #expect(store.moments(for: id) == [expected])
        let reopened = try #require(SermonStore(configuration: .uiTest(directory: root)).moments(for: id).first)
        #expect(reopened.id == original.id && reopened.sermonID == original.sermonID)
        #expect(reopened.time == original.time && reopened.audioAssetID == original.audioAssetID)
        #expect(reopened.note == "Revised reflection")
        // Version 1 stores creation dates at ISO-8601 whole-second precision.
        #expect(abs(reopened.createdAt.timeIntervalSince(original.createdAt)) < 1)
        edit.sermonID = UUID()
        #expect(throws: SermonSetError.self) { try store.updateMoment(edit) }
        #expect(store.moments(for: id) == [expected])
        edit = original; edit.note = nil
        try store.updateMoment(edit)
        #expect(store.moments(for: id).first?.note == nil)
    }
    @Test func noteOrderingAndSampleRemoval() throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.discoverCatalog.first?.id)
        let untimed = try store.addNote(sermonID: id, text: "Untimed", time: nil)
        let later = try store.addNote(sermonID: id, text: "Later", time: 15)
        let earlier = try store.addNote(sermonID: id, text: "Earlier", time: 3)
        let ordered = store.notes(for: id).map(\.id)
        #expect(ordered.firstIndex(of: earlier.id)! < ordered.firstIndex(of: later.id)!)
        #expect(ordered.firstIndex(of: later.id)! < ordered.firstIndex(of: untimed.id)!)
        #expect(throws: SermonSetError.self) { try store.addMoment(sermonID: id, time: .nan, note: nil) }
        try store.removeSampleSermons()
        #expect(store.libraryEntries.isEmpty && store.binder.isEmpty && !store.hasSamplesInLibrary)
        #expect(store.discoverCatalog.count == 8)
    }
    @Test func listeningProgressIsThrottledAndCompletionIsDurable() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try store.addSampleSermons(); let id = try #require(store.libraryEntries.first?.id)
        store.recordListening(sermonID: id, position: 10, duration: 100)
        store.recordListening(sermonID: id, position: 11, duration: 100)
        #expect(store.entry(for: id)?.history.listeningPosition == 10)
        store.recordListening(sermonID: id, position: 95, duration: 100)
        #expect(store.entry(for: id)?.history.completedAt != nil)
        #expect(SermonStore(configuration: .uiTest(directory: root)).entry(for: id)?.history.listeningPosition == 95)
    }
    @Test func failedAtomicWriteDoesNotPublishState() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try FileManager.default.createDirectory(at: store.storeURL, withIntermediateDirectories: true)
        #expect(throws: SermonSetError.self) { try store.addSampleSermons() }
        #expect(store.libraryEntries.isEmpty && store.binder.isEmpty)
        #expect(store.lastError != nil)
    }
}

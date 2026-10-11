import Testing
import Foundation
@testable import SermonSetCore
@Suite @MainActor struct ArchiveTests {
    @Test func archiveRoundTripMergeAndWrongPassphrase() async throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let b = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let source = SermonStore(configuration: .uiTest(directory: a))
        try source.keepSample(source.discoverCatalog[0].id)
        let id = source.libraryEntries[0].id
        let note = try source.addNote(sermonID: id,text: "private words",time: 1)
        _ = try source.addMoment(sermonID: id,time: 2,note: "private moment")
        let zip = try await source.exportLibraryBackup()
        let destination = SermonStore(configuration: .uiTest(directory: b))
        #expect(try await destination.restoreLibraryBackup(from: zip).addedSermons == 1)
        #expect(destination.notes(for: id).map(\.id) == [note.id])
        #expect(destination.notes(for: id).first?.text == note.text)
        #expect(destination.moments(for: id).count == 1)
        #expect(destination.transcript(for: id) != nil)
        #expect(try await destination.restoreLibraryBackup(from: zip).addedSermons == 0)
        #expect(destination.binder.count == 1)
        let encrypted = try await source.exportLibraryBackup(passphrase: "test passphrase")
        await #expect(throws: SermonSetError.self) { try await destination.restoreLibraryBackup(from: encrypted,passphrase: "wrong") }
        #expect(try await destination.restoreLibraryBackup(from: encrypted,passphrase: "test passphrase").addedSermons == 0)
    }
    @Test func corruptionAndTraversalFail() throws {
        #expect(!LibraryZIP.safe("audio/../../escape"))
        #expect(!LibraryZIP.safe("/absolute"))
        #expect(!LibraryZIP.safe("audio\\escape"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: SermonSetError.self) { try LibraryZIP.extract(Data("not ZIP".utf8),to: dir) }
        let wrapped = try WrappedSecret.wrap(Data("secret".utf8),passphrase: "passphrase")
        var corrupted = wrapped; corrupted.sealed[corrupted.sealed.count-1] ^= 1
        #expect(throws: SermonSetError.self) { try corrupted.open(passphrase: "passphrase") }
    }
}

extension ArchiveTests {
    @Test func restoreRecoversUnreadableStoreWithoutReplacingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try store.keepSample(store.discoverCatalog[0].id)
        let backup = try await store.exportLibraryBackup()
        try Data("invalid store".utf8).write(to: root.appendingPathComponent("store.json"))
        let broken = SermonStore(configuration: .uiTest(directory: root))
        #expect(broken.writesBlocked)
        #expect(try await broken.restoreLibraryBackup(from: backup).addedSermons == 1)
        #expect(!broken.writesBlocked)
        #expect(broken.libraryEntries.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("store-corrupt-") })
    }
}

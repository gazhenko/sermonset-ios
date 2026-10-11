import Foundation
import Testing
@testable import SermonSetCore

@MainActor private final class ChoiceFixtureEngine: SermonNotesEngine {
    var status: CapabilityStatus
    var calls = 0
    var name: String
    init(status: CapabilityStatus = .available, name: String) { self.status = status; self.name = name }
    func capability(localeIdentifier: String) -> CapabilityStatus { status }
    func generate(transcript: Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult {
        calls += 1
        return NotesGenerationResult(notes: SermonNotes(bigIdea: "Patient trust guides practical care.", points: [], engine: name))
    }
}
@MainActor @Suite struct NotesEngineChoiceTests {
    @Test func olderLibraryDefaultsToAppleAndChoicePersists() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures", isDirectory: true).appendingPathComponent("Sower-choice-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        #expect(store.notesEngine == .appleIntelligence)
        store.notesEngine = .openSource
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        #expect(reopened.lastError == nil && reopened.notesEngine == .openSource)
        var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("store.json"))) as? [String: Any])
        old.removeValue(forKey: "notesEngine")
        try JSONSerialization.data(withJSONObject: old).write(to: root.appendingPathComponent("store.json"))
        #expect(SermonStore(configuration: .uiTest(directory: root)).notesEngine == .appleIntelligence)
    }
    @Test func notReadyOrMissingLocalEngineFallsBackWithProvenance() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures", isDirectory: true).appendingPathComponent("Sower-fallback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let apple = ChoiceFixtureEngine(name: "Apple Intelligence (on-device)")
        let local = ChoiceFixtureEngine(status: .needsDownload, name: "Qwen 3.5 4B (on-device)")
        let store = SermonStore(configuration: .uiTest(directory: root), notesEngine: apple)
        let transcript = NotesTests().source()
        store.notesEngine = .openSource
        let missing = try await store.draftNotes(sermonID: transcript.sermonID, transcript: transcript)
        #expect(missing.notes?.engine == apple.name && missing.unavailableReason?.contains("not downloaded") == true)
        store.setOpenSourceNotesEngine(local)
        let paused = try await store.draftNotes(sermonID: transcript.sermonID, transcript: transcript)
        #expect(paused.notes?.engine == apple.name && local.calls == 0 && apple.calls == 2)
        local.status = .available
        let ready = try await store.draftNotes(sermonID: transcript.sermonID, transcript: transcript, knownModelStatus: .unavailable(reason: "Apple is off"))
        #expect(ready.notes?.engine == local.name && ready.unavailableReason == nil && local.calls == 1 && apple.calls == 2)
        store.notesEngine = .appleIntelligence
        _ = try await store.draftNotes(sermonID: transcript.sermonID, transcript: transcript)
        #expect(apple.calls == 3 && local.calls == 1)
    }
    @Test func bothUnavailableDoNotInventNotes() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures", isDirectory: true).appendingPathComponent("Sower-unavailable-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let apple = ChoiceFixtureEngine(status: .unavailable(reason: "Apple Intelligence is off."), name: "Apple")
        let store = SermonStore(configuration: .uiTest(directory: root), notesEngine: apple)
        store.notesEngine = .openSource
        let transcript = NotesTests().source()
        let result = try await store.draftNotes(sermonID: transcript.sermonID, transcript: transcript)
        #expect(result.notes == nil && result.unavailableReason?.contains("Apple Intelligence is off") == true && apple.calls == 0)
    }
}

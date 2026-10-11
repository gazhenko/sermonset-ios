import Foundation

public enum NotesEngineChoice: String, Codable, CaseIterable, Sendable {
    case appleIntelligence, openSource
}

extension SermonStore {
    public var notesEngine: NotesEngineChoice {
        get { document.notesEngine ?? .appleIntelligence }
        set { do { try transaction { $0.notesEngine = newValue } } catch { _ = report(error) } }
    }

    /// The app supplies its optional engine; Core never imports its implementation.
    public func setOpenSourceNotesEngine(_ engine: any SermonNotesEngine) {
        openSourceNotesEngine = engine
    }
}

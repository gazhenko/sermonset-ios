import Foundation
import SermonSetCore
import SwiftUI

/// Every user-facing phrase for core enums lives here so the copy stays consistent.
enum Format {
    /// "4:07", "1:02:33"
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "2 min", "48 min", "1 hr 4 min"
    static func length(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Under a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "Under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static func spokenClock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m) minutes \(s) seconds" : "\(s) seconds"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func storage(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func hoursRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "No recording space left" }
        let hours = seconds / 3600
        if hours >= 100 { return "Room for \(Int(hours).formatted()) hours of recording" }
        if hours >= 2 { return "About \(Int(hours)) hours of recording space" }
        return "About \(Int(seconds / 60)) minutes of recording space"
    }

    static func place(_ venue: Venue?) -> String? {
        guard let venue else { return nil }
        switch venue.precision {
        case .privateLocation: return "Location private"
        case .unknown where venue.city == nil: return nil
        default: break
        }
        let parts = [venue.city, venue.region].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func church(_ venue: Venue?) -> String? {
        guard let name = venue?.churchName, !name.isEmpty, venue?.precision != .privateLocation else { return nil }
        return name
    }

    static func title(_ sermon: Sermon) -> String {
        sermon.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled sermon" : sermon.title
    }
}

extension SermonType {
    var displayName: String {
        switch self {
        case .hope: "Hope"
        case .wisdom: "Wisdom"
        case .grace: "Grace"
        case .courage: "Courage"
        case .conviction: "Conviction"
        case .worship: "Worship"
        case .mission: "Mission"
        case .restoration: "Restoration"
        }
    }
}

extension EncounterSource {
    var displayName: String {
        switch self {
        case .recorded: "You recorded this"
        case .imported: "Imported audio"
        case .sundayPack: "From a Sunday Pack"
        case .trade: "Received in a trade"
        case .shared: "Shared with you"
        case .sample: "Sample sermon"
        case .discover: "Kept from Discover"
        }
    }

    var filterName: String {
        switch self {
        case .recorded: "Recorded"
        case .imported: "Imported"
        case .sundayPack: "Packs"
        case .trade: "Trades"
        case .shared: "Shared"
        case .sample: "Samples"
        case .discover: "Discover"
        }
    }
}

extension TrustState {
    var displayName: String {
        switch self {
        case .personalDraft: "Personal draft"
        case .communityMatched: "Matched by the community"
        case .churchVerified: "Verified by the church"
        }
    }

    var shortName: String {
        switch self {
        case .personalDraft: "Personal draft"
        case .communityMatched: "Community matched"
        case .churchVerified: "Church verified"
        }
    }

    var explanation: String {
        switch self {
        case .personalDraft: "Only you have this record. It hasn’t been matched to a church service."
        case .communityMatched: "Matched to a known service by listeners. The church hasn’t confirmed it."
        case .churchVerified: "The church confirmed the title, preacher, and date. This isn’t a theological endorsement."
        }
    }
}

extension RightsState {
    var displayName: String {
        switch self {
        case .privateOnly: "Private on this iPhone"
        case .audioAuthorized: "Audio shared with permission"
        case .officialAudio: "Official church audio"
        case .disputed: "Audio under review"
        case .audioRemoved: "Audio removed"
        case .noAudio: "No audio"
        }
    }

    var shortName: String {
        switch self {
        case .privateOnly: "Private"
        case .audioAuthorized: "Shared with permission"
        case .officialAudio: "Official church audio"
        case .disputed: "Under review"
        case .audioRemoved: "Removed"
        case .noAudio: "None"
        }
    }

    var explanation: String {
        switch self {
        case .privateOnly: "Your recording stays on this iPhone. Recording it doesn’t give anyone permission to share it."
        case .audioAuthorized: "The church or preacher allowed this audio to be played by others."
        case .officialAudio: "The church supplied this recording."
        case .disputed: "Playback is paused while a rights or privacy concern is reviewed. The sermon stays in your library."
        case .audioRemoved: "Playback was turned off. The sermon, your notes, and your card stay."
        case .noAudio: "There’s no audio for this sermon."
        }
    }

    var systemImage: String {
        switch self {
        case .privateOnly: "lock.fill"
        case .audioAuthorized: "checkmark.seal"
        case .officialAudio: "building.columns"
        case .disputed: "exclamationmark.triangle"
        case .audioRemoved, .noAudio: "speaker.slash"
        }
    }
}

extension AudioAssetKind {
    var displayName: String {
        switch self {
        case .original: "Your original recording"
        case .imported: "Imported audio"
        case .enhanced: "Voice Focus copy"
        case .official: "Official church audio"
        case .sample: "Sample narration"
        }
    }
}

extension ReviewState {
    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .reviewed: "Kept by you"
        case .rejected: "Set aside"
        }
    }
}

extension CapabilityStatus {
    var isAvailable: Bool { if case .available = self { true } else { false } }

    var displayText: String {
        switch self {
        case .available: "Ready on this iPhone"
        case .needsDownload: "Needs a one-time download"
        case .unavailable(let reason): reason
        }
    }
}

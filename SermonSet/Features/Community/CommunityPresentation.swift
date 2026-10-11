import SermonSetCore
import SwiftUI

extension CardFaceModel {
    /// A community sermon's card, before or after the listener keeps it.
    @MainActor
    init(community sermon: CommunitySermon, card: CommunityCard? = nil, churchName: String? = nil) {
        let trust: TrustState = sermon.trustLabels.contains("Church verified") ? .churchVerified : .communityMatched
        let rights = CommunityRights(sermon)
        let place = [sermon.city, sermon.region].compactMap { $0 }.joined(separator: ", ")
        self.init(
            title: sermon.title,
            preacher: sermon.preacher,
            church: churchName,
            place: place.isEmpty ? nil : place,
            passage: sermon.primaryPassage.isEmpty ? nil : sermon.primaryPassage,
            typeKey: sermon.sermonType,
            typeName: SermonType(rawValue: sermon.sermonType)?.displayName ?? "Sermon",
            dateText: Format.date(sermon.serviceDate),
            editionText: card.map { "\($0.edition) edition" } ?? (sermon.fictional ? "Sample edition" : "Community edition"),
            serialText: card.map { String(format: "%03d", $0.serialNumber) } ?? "—",
            seed: (card?.editionID ?? sermon.id).unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) },
            bigIdea: sermon.summary,
            reflection: sermon.reflectionPrompt,
            themes: sermon.themes,
            durationText: nil,
            trustText: trust.displayName,
            trustShort: trust.shortName,
            audioText: rights.state.displayName,
            audioShort: rights.state.shortName,
            isSample: sermon.fictional,
            featuredMoment: nil
        )
    }
}

/// What a community sermon's audio is allowed to do right now, from the server's trust labels.
struct CommunityRights {
    var state: RightsState
    init(_ sermon: CommunitySermon) {
        let labels = Set(sermon.trustLabels)
        if labels.contains("Disputed") { state = .disputed }
        else if labels.contains("Audio removed") { state = .audioRemoved }
        else if !sermon.audioAvailable { state = .noAudio }
        else if labels.contains("Official audio") { state = .officialAudio }
        else { state = .audioAuthorized }
    }
    var canListen: Bool { state == .audioAuthorized || state == .officialAudio }
    var unavailableReason: String? {
        switch state {
        case .disputed: "The audio is paused while the church reviews it. The card and its details stay yours."
        case .audioRemoved: "The audio was removed. The card and its details stay yours."
        case .noAudio: "Only the details were shared. There’s no audio to play."
        default: nil
        }
    }
}

/// Plain words for the server's labels. Labels describe how a record was checked, never an endorsement.
enum TrustLabelCopy {
    static func explain(_ label: String) -> String {
        switch label {
        case "Community matched": "Listeners matched it to a real service. The church hasn’t confirmed it."
        case "Church verified": "The church confirmed this sermon was preached."
        case "Audio authorized": "The church gave permission for this audio to be shared."
        case "Official audio": "The church uploaded this audio itself."
        case "Disputed": "Someone raised a concern, and it’s being reviewed."
        case "Audio removed": "The audio is no longer available."
        default: label
        }
    }
    static func symbol(_ label: String) -> String {
        switch label {
        case "Church verified": "checkmark.seal"
        case "Audio authorized", "Official audio": "waveform"
        case "Disputed": "exclamationmark.bubble"
        case "Audio removed": "speaker.slash"
        default: "person.2"
        }
    }
}

struct TrustLabelRow: View {
    @Environment(\.look) private var look
    var labels: [String]

    var body: some View {
        if !labels.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Label(label, systemImage: TrustLabelCopy.symbol(label))
                        .font(look.type.caption)
                        .foregroundStyle(label == "Disputed" || label == "Audio removed" ? look.palette.record : look.palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(look.palette.surfaceRaised))
                        .overlay(Capsule().strokeBorder(look.palette.rule, lineWidth: look.shape.borderWidth > 0 ? 1 : 0))
                        .accessibilityLabel("\(label). \(TrustLabelCopy.explain(label))")
                }
            }
        }
    }
}

/// Inbox notices in the listener's words.
struct InboxCopy {
    var title: String
    var detail: String
    var symbol: String

    init(_ type: String) {
        switch type {
        case "offerReceived": (title, detail, symbol) = ("Someone offered you a card", "Open it to look before you accept.", "gift")
        case "offerAccepted": (title, detail, symbol) = ("A card changed hands", "The trade went through. The sermon stays in both libraries.", "arrow.left.arrow.right")
        case "offerProposed": (title, detail, symbol) = ("A swap was proposed", "Look at the card they offered and confirm or cancel.", "arrow.triangle.swap")
        case "offerDeclined": (title, detail, symbol) = ("An offer was declined", "Nothing moved. The card is still yours.", "xmark.circle")
        case "offerCancelled": (title, detail, symbol) = ("An offer was cancelled", "Nothing moved.", "xmark.circle")
        case "offerExpired": (title, detail, symbol) = ("An offer expired", "Offers last up to seven days. Nothing moved.", "clock")
        case "publicationSubmitted": (title, detail, symbol) = ("Your share was received", "It’s being checked before anyone can see it.", "tray.and.arrow.up")
        case "publicationPendingRights": (title, detail, symbol) = ("Waiting for the church", "The church reviews shared recordings before they go public.", "hourglass")
        case "publicationPublished": (title, detail, symbol) = ("Your sermon is shared", "Others can now find it in Discover.", "checkmark.seal")
        case "publicationRejected": (title, detail, symbol) = ("Your share wasn’t published", "Your recording is still private on your iPhone.", "xmark.seal")
        case "churchDecision": (title, detail, symbol) = ("The church made a decision", "Open the sermon to see what changed.", "building.columns")
        case "churchClaimApproved": (title, detail, symbol) = ("Church claim approved", "You can now manage your church in the web portal.", "building.columns")
        case "churchClaimRejected": (title, detail, symbol) = ("Church claim not approved", "Contact the moderators if you think this is a mistake.", "building.columns")
        case "reportSubmitted": (title, detail, symbol) = ("Report received", "Thanks. A moderator will look at it.", "flag")
        case "removalCompleted": (title, detail, symbol) = ("Removal completed", "The audio you asked about is no longer available.", "speaker.slash")
        case "accountBanned": (title, detail, symbol) = ("Your account was restricted", "You can still use everything on this iPhone. You can appeal from the web.", "exclamationmark.octagon")
        case "accountRestored": (title, detail, symbol) = ("Your account was restored", "Trading and sharing are available again.", "checkmark.circle")
        default:
            if type.hasPrefix("moderation") {
                (title, detail, symbol) = ("A moderator updated something of yours", "Open it to see what changed.", "shield")
            } else {
                (title, detail, symbol) = ("Update", "Something changed in your community account.", "bell")
            }
        }
    }
}

enum OfferCopy {
    static func state(_ offer: CommunityOffer, mine: Bool) -> String {
        switch offer.state {
        case "open": mine ? "Waiting for them" : "Waiting for you"
        case "proposed": mine ? "They proposed a swap — your turn" : "Waiting for them to confirm"
        case "accepted": "Done"
        case "declined": "Declined"
        case "cancelled": "Cancelled"
        case "expired": "Expired"
        default: offer.state.capitalized
        }
    }
    static func kind(_ offer: CommunityOffer) -> String { offer.kind == "swap" ? "Swap" : "Gift" }
    static func isLive(_ offer: CommunityOffer) -> Bool { offer.state == "open" || offer.state == "proposed" }
}

/// Avatar styles are drawn shapes, never photos.
enum AvatarStyle: String, CaseIterable, Identifiable {
    case plain, leaf, flame, drop, sun, star, wave
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .plain: "circle.fill"
        case .leaf: "leaf.fill"
        case .flame: "flame.fill"
        case .drop: "drop.fill"
        case .sun: "sun.max.fill"
        case .star: "star.fill"
        case .wave: "water.waves"
        }
    }
    var name: String {
        switch self {
        case .plain: "Plain"
        case .leaf: "Leaf"
        case .flame: "Flame"
        case .drop: "Drop"
        case .sun: "Sun"
        case .star: "Star"
        case .wave: "Wave"
        }
    }
}

struct AvatarView: View {
    @Environment(\.look) private var look
    var style: String
    var name: String?
    var size: CGFloat = 44

    var body: some View {
        let avatar = AvatarStyle(rawValue: style) ?? .plain
        ZStack {
            Circle().fill(look.palette.accent)
            if avatar == .plain, let initial = name?.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(look.palette.onAccent)
            } else {
                Image(systemName: avatar == .plain ? "person.fill" : avatar.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(look.palette.onAccent)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(look.palette.ink, lineWidth: look.id == .riso ? 2 : 0))
        .accessibilityHidden(true)
    }
}

/// Shown above community content when the last refresh failed.
struct CommunityStatusNote: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    var retry: () async -> Void

    var body: some View {
        if community.isOffline || community.lastError != nil {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: community.isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    .foregroundStyle(look.palette.inkSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(community.isOffline ? "You’re offline. Showing what was saved last time." : (community.lastError ?? ""))
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await retry() } }
                        .font(look.type.callout.weight(.semibold))
                        .foregroundStyle(look.palette.accent)
                }
                Spacer(minLength: 0)
            }
            .lookPanel(padding: 12)
            .accessibilityElement(children: .combine)
        }
    }
}

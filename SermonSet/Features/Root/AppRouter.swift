import Observation
import SermonSetCore
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case library, discover, collection

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .library: "Library"
        case .discover: "Discover"
        case .collection: "Collection"
        }
    }

    var name: String {
        switch self {
        case .library: "Library"
        case .discover: "Discover"
        case .collection: "Collection"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .discover: "sparkles"
        case .collection: "square.stack"
        }
    }
}

struct IncomingOffer: Identifiable, Hashable {
    var token: String
    var id: String { token }
}

struct CommunitySermonRoute: Identifiable, Hashable {
    var id: String
}

enum Route: Hashable {
    case sermon(UUID)
    case transcript(UUID)
    case church(String)
}

/// Navigation state shared by every screen.
@MainActor @Observable
final class AppRouter {
    var tab: AppTab = .library
    var libraryPath: [Route] = []
    var discoverPath: [Route] = []
    var collectionPath: [Route] = []
    var isRecorderPresented = false
    var isSettingsPresented = false
    var isPackPresented = false
    var isImporterPresented = false
    var cardViewerSermonID: UUID?
    var isInboxPresented = false
    /// An offer link or QR someone gave the listener, waiting to be reviewed.
    var incomingOffer: IncomingOffer?
    var communitySermon: CommunitySermonRoute?
    /// An existing offer opened from the inbox or the offers list.
    var openedOfferID: String?

    func openOffer(id: String) {
        openedOfferID = id
    }

    /// `sower://t/<token>`, `sower://s/<sermonID>`, and the matching https links.
    func handle(_ url: URL) {
        let parts = url.scheme == "https" || url.scheme == "http"
            ? url.pathComponents.filter { $0 != "/" }
            : [url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "t", "offer": incomingOffer = IncomingOffer(token: parts[1])
        case "s", "sermon":
            cardViewerSermonID = nil
            communitySermon = CommunitySermonRoute(id: parts[1])
        default: break
        }
    }

    func openSermon(_ id: UUID) {
        cardViewerSermonID = nil
        tab = .library
        if libraryPath.last != .sermon(id) {
            libraryPath = [.sermon(id)]
        }
    }

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: {
                switch tab {
                case .library: self.libraryPath
                case .discover: self.discoverPath
                case .collection: self.collectionPath
                }
            },
            set: { newValue in
                switch tab {
                case .library: self.libraryPath = newValue
                case .discover: self.discoverPath = newValue
                case .collection: self.collectionPath = newValue
                }
            }
        )
    }
}

extension View {
    func sermonDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .sermon(let id): SermonDetailView(sermonID: id)
            case .transcript(let id): TranscriptView(sermonID: id)
            case .church(let id): ChurchView(churchID: id)
            }
        }
    }
}

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

enum Route: Hashable {
    case sermon(UUID)
    case transcript(UUID)
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
            }
        }
    }
}

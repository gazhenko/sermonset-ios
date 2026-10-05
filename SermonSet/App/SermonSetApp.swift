import SermonSetCore
import SwiftUI

@main
struct SermonSetApp: App {
    @State private var store: SermonStore
    @State private var capture: CaptureController
    @State private var playback: PlaybackController
    @State private var router = AppRouter()
    @AppStorage(LookID.storageKey) private var lookRaw = LookID.riso.rawValue

    private let lookLabSide: CardSide?

    init() {
        let store = SermonStore(configuration: .fromLaunchArguments())
        _store = State(initialValue: store)
        _capture = State(initialValue: CaptureController(store: store))
        _playback = State(initialValue: PlaybackController(store: store))

        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-SermonSetLookLab") {
            lookLabSide = args.indices.contains(index + 1) && args[index + 1] == "back" ? .back : .front
        } else {
            lookLabSide = nil
        }
        // Seeds the saved look without pinning it (a `-SermonSetLook` argument pins it for the launch).
        if let index = args.firstIndex(of: "-SermonSetInitialLook"), args.indices.contains(index + 1) {
            UserDefaults.standard.set(args[index + 1], forKey: LookID.storageKey)
        }
        if args.contains("-SermonSetPreviewData") || args.contains("-SermonSetSkipOnboarding") {
            UserDefaults.standard.set(true, forKey: "SermonSetOnboarded")
        }
        if let screen = DebugLaunchRoute.requested {
            UserDefaults.standard.set(screen == "atlas" ? "atlas" : "binder", forKey: "SermonSetCollectionMode")
        }
    }

    private var look: Look { Look.of(LookID(rawValue: lookRaw) ?? .riso) }

    var body: some Scene {
        WindowGroup {
            Group {
                if let lookLabSide {
                    LookLab(models: LookLab.sampleModels(store), side: lookLabSide)
                } else {
                    RootView()
                }
            }
            .environment(store)
            .environment(capture)
            .environment(playback)
            .environment(router)
            .lookScoped(look)
            .onOpenURL { _ in }
        }
    }
}

import SermonSetCore
import SermonSetLocalModel
import SermonSetSpeech
import SwiftUI

@main
struct SermonSetApp: App {
    @State private var store: SermonStore
    @State private var localModel: LocalModelManager
    @State private var speechModels: SpeechModelManager
    @State private var capture: CaptureController
    @State private var playback: PlaybackController
    @State private var community: CommunityController
    @State private var publishing: PublishingController
    @State private var communityPlayback: CommunityPlaybackController
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LookID.storageKey) private var lookRaw = LookID.sower.rawValue

    private let lookLabSide: CardSide?

    init() {
        SowerType.registerFonts()
        let localModel = LocalModelManager()
        let store = SermonStore(configuration: .fromLaunchArguments(), openSourceNotesEngine: LocalQwenNotesEngine(manager: localModel))
        _store = State(initialValue: store)
        _localModel = State(initialValue: localModel)
        AppDelegate.localModel = localModel
        // Parakeet transcription is installed before any recording processing resumes.
        let speechModels = SpeechModelManager()
        speechModels.install(in: store)
        _speechModels = State(initialValue: speechModels)
        AppDelegate.speechModels = speechModels
        _capture = State(initialValue: CaptureController(store: store))
        _playback = State(initialValue: PlaybackController(store: store))
        let community = CommunityController(store: store)
        _community = State(initialValue: community)
        let publishing = PublishingController(store: store, community: community)
        _publishing = State(initialValue: publishing)
        _communityPlayback = State(initialValue: CommunityPlaybackController(community: community))
        AppDelegate.publishing = publishing

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
        if MediaRender.requested { MediaRender.run(store: store) }
        if let screen = DebugLaunchRoute.requested {
            UserDefaults.standard.set(screen == "atlas" ? "atlas" : "binder", forKey: "SermonSetCollectionMode")
        }
    }

    private var look: Look { Look.of(LookID(rawValue: lookRaw) ?? .sower) }

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
            .environment(localModel)
            .environment(speechModels)
            .task { await LocalModelDebug.configure(store: store, manager: localModel) }
            // DEBUG-only download/compare hooks; release builds return immediately.
            .task { try? await speechModels.runLaunchArguments(store: store) }
            .onChange(of: speechModels.isReady) { Task { await store.refreshCapabilities() } }
            .environment(capture)
            .environment(playback)
            .environment(community)
            .environment(publishing)
            .environment(communityPlayback)
            .environment(router)
            .lookScoped(look)
            .onOpenURL { router.handle($0) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    community.foreground()
                    Task { await publishing.process() }
                } else {
                    community.background()
                }
            }
        }
    }
}

/// Hands background transfer events to their owners: shared-sermon uploads and the optional model downloads.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var publishing: PublishingController?
    @MainActor static var localModel: LocalModelManager?
    @MainActor static var speechModels: SpeechModelManager?

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            if identifier == SpeechModelManager.backgroundSessionIdentifier {
                // The transcription model finishing its download while SOWER was in the background.
                AppDelegate.speechModels?.handleBackgroundEvents(identifier: identifier) { completionHandler() }
            } else if identifier == LocalModelManager.backgroundSessionIdentifier {
                // The optional notes model finishing its download while SOWER was in the background.
                AppDelegate.localModel?.handleBackgroundEvents(identifier: identifier) { completionHandler() }
            } else {
                AppDelegate.publishing?.handleBackgroundSession(identifier: identifier) { completionHandler() }
            }
        }
    }
}

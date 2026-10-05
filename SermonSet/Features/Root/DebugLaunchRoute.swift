import SermonSetCore
import SwiftUI

/// Opens a specific screen at launch for design review and screenshots:
/// `-SermonSetScreen library|sermon|transcript|record|discover|pack|binder|atlas|card|settings|onboarding`
enum DebugLaunchRoute {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-SermonSetScreen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// `-SermonSetScroll takeaways|transcript|notes|card|details` scrolls the sermon page for review.
    static var scrollAnchor: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-SermonSetScroll"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    @MainActor
    static func apply(router: AppRouter, store: SermonStore, capture: CaptureController) {
        guard let screen = requested else { return }
        let first = store.libraryEntries.first { $0.sermon.isSample }?.id ?? store.libraryEntries.first?.id
        switch screen {
        case "sermon": if let first { router.libraryPath = [.sermon(first)] }
        case "transcript": if let first { router.libraryPath = [.sermon(first), .transcript(first)] }
        case "record": router.isRecorderPresented = true
        case "recording":
            // Simulated engine only: start a session and mark two moments so the live screen has content.
            guard ProcessInfo.processInfo.arguments.contains("-SermonSetSimulatedCapture") else { return }
            router.isRecorderPresented = true
            Task {
                try? await capture.start(CaptureDraft(title: "Morning service", churchName: "Grace Harbor"))
                try? await Task.sleep(for: .seconds(2.5))
                capture.markMoment()
                try? await Task.sleep(for: .seconds(1.5))
                capture.addNote("Peace is presence, not absence")
                capture.markMoment()
            }
        case "playing":
            if let first { router.tab = .discover; Task { try? await Task.sleep(for: .seconds(0.5)); NotificationCenter.default.post(name: .debugPlay, object: first) } }
        case "hidden-recording":
            guard ProcessInfo.processInfo.arguments.contains("-SermonSetSimulatedCapture") else { return }
            Task { try? await capture.start(CaptureDraft(title: "Evening service")) }
        case "transcribe-demo":
            // Imports one sample narration as if it were the listener's own audio, then runs the real
            // on-device transcription and takeaway jobs so their states can be reviewed.
            Task {
                guard let sample = store.discoverCatalog.first(where: { $0.title == "Open Hands" }) ?? store.discoverCatalog.first,
                      let asset = store.audioAssets(for: sample.id).first,
                      let url = store.audioURL(for: asset),
                      let sermon = try? await store.importAudio(from: url, title: "Imported narration test") else { return }
                router.openSermon(sermon.id)
                await store.transcribe(sermonID: sermon.id)
                if store.transcript(for: sermon.id) != nil {
                    await store.generateInsights(sermonID: sermon.id)
                }
            }
        case "insights-demo":
            // Regenerates takeaways for a sample from its transcript with whatever on-device model is available.
            guard let first else { return }
            router.libraryPath = [.sermon(first)]
            Task { await store.generateInsights(sermonID: first) }
        case "discover": router.tab = .discover
        case "pack": router.tab = .discover; router.isPackPresented = true
        case "binder": router.tab = .collection
        case "atlas":
            router.tab = .collection
            UserDefaults.standard.set("atlas", forKey: "SermonSetCollectionMode")
        case "card": router.cardViewerSermonID = store.binder.first?.sermonID ?? first
        case "settings": router.isSettingsPresented = true
        case "onboarding": UserDefaults.standard.set(false, forKey: "SermonSetOnboarded")
        default: break
        }
    }
}

extension Notification.Name {
    static let debugPlay = Notification.Name("SermonSetDebugPlay")
}

import SermonSetCore
import SwiftUI

/// Renders marketing art with transparent backgrounds for the website and README:
/// `-SowerRenderMedia` writes PNGs to the app's Documents/media folder, then quits.
enum MediaRender {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-SowerRenderMedia") }

    @MainActor
    static func run(store: SermonStore) {
        let titles = ["When Faith Gets Loud", "Peace in the Storm", "Open Hands"]
        let sermons = titles.compactMap { title in store.discoverCatalog.first { $0.title == title } }
        let models = (sermons.isEmpty ? Array(store.discoverCatalog.prefix(3)) : sermons).map { CardFaceModel(sermon: $0, store: store) }
        let folder = URL.documentsDirectory.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for id in LookID.allCases {
            let look = Look.of(id)
            let art = HeroFan(models: models)
                .environment(\.look, look)
                .frame(width: 900, height: 620)
            let renderer = ImageRenderer(content: art)
            renderer.scale = 2
            renderer.isOpaque = false
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: folder.appendingPathComponent("hero-cards-\(id.rawValue).png"))
            }
        }
    }
}

private struct HeroFan: View {
    var models: [CardFaceModel]

    var body: some View {
        ZStack {
            ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                let offset = Double(index) - Double(models.count - 1) / 2
                SermonCardFace(model: model)
                    .frame(width: 300)
                    .rotationEffect(.degrees(offset * 12), anchor: .bottom)
                    .offset(x: offset * 210, y: abs(offset) * 26 + 10)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
    }
}

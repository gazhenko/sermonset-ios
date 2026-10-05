import SermonSetCore
import SwiftUI

/// Design review surface: every look's card front and back side by side.
/// Launch with `-SermonSetLookLab` to open it directly.
struct LookLab: View {
    var models: [CardFaceModel] = [.preview]
    var side: CardSide = .front

    private var items: [(key: String, look: LookID, model: CardFaceModel)] {
        models.enumerated().flatMap { index, model in
            LookID.allCases.map { (key: "\($0.rawValue)-\(index)", look: $0, model: model) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(items, id: \.key) { item in
                    VStack(spacing: 6) {
                        SermonCardFace(model: item.model, side: side, lookID: item.look)
                        Text(Look.of(item.look).name).font(.caption.bold())
                    }
                }
            }
            .padding(12)
        }
        .background(Color(white: 0.5))
    }
}

extension LookLab {
    @MainActor
    static func sampleModels(_ store: SermonStore) -> [CardFaceModel] {
        let samples = store.discoverCatalog.prefix(2).map { CardFaceModel(sermon: $0, store: store) }
        return samples.isEmpty ? [.preview] : Array(samples)
    }
}

import SermonSetCore
import SwiftUI

/// "Suggest the church I'm at": one location fix, nearby churches to pick from, nothing saved.
struct VenueSuggestions: View {
    @Environment(\.look) private var look
    @State private var controller = VenueSuggestionController()
    var onPick: (VenueCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch controller.state {
            case .idle, .done where controller.candidates.isEmpty:
                Button {
                    controller.suggest()
                } label: {
                    Label("Suggest the church I’m at", systemImage: "location")
                }
                .buttonStyle(.look(.secondary))
                if case .done = controller.state {
                    Text("No churches found nearby. Type it in instead.").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().tint(look.palette.accent)
                    Text("Looking for nearby churches…").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                    Spacer()
                    Button("Cancel") { controller.cancel() }.buttonStyle(.look(.quiet))
                }
            case .unavailable(let reason), .failed(let reason):
                Label(reason, systemImage: "location.slash").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                Text("Which one?").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                ForEach(controller.candidates.prefix(6)) { candidate in
                    Button {
                        onPick(candidate)
                        controller.cancel()
                    } label: {
                        HStack {
                            Image(systemName: "building.columns").foregroundStyle(look.palette.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.churchName).font(look.type.headline).foregroundStyle(look.palette.ink)
                                Text([candidate.city, candidate.region].compactMap { $0 }.joined(separator: ", "))
                                    .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Your location is used once for this suggestion and never saved or shared. A place doesn’t give anyone permission to share a recording.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

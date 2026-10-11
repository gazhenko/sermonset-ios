import SermonSetCore
import SermonSetSpeech
import SwiftUI

/// Which on-device recognizer turns recordings into text. Parakeet is the accurate one and needs a one-time
/// download; Apple's is built in. Either way the audio never leaves the iPhone.
struct TranscriptionEngineSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(SpeechModelManager.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription").font(look.type.headline).foregroundStyle(look.palette.ink)
            choice(.parakeet,
                   title: "Parakeet (recommended)",
                   detail: "Open-source (NVIDIA Parakeet, run on the Neural Engine). In our tests it made about a third fewer mistakes on room recordings than Apple’s recognizer, and it labels who’s speaking. A \(Self.size(SpeechModelConfiguration.sizeBytes)) download.")
            choice(.apple,
                   title: "Apple",
                   detail: "Built into iOS. No download.")
            if store.transcriptionEngine == .parakeet || !model.isReady {
                status.padding(.leading, 34)
            }
            if let reason = store.transcriptionFallbackReason, store.transcriptionEngine == .parakeet {
                Label(reason, systemImage: "info.circle")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choice(_ engine: TranscriptionEngineChoice, title: LocalizedStringKey, detail: String) -> some View {
        let isOn = store.transcriptionEngine == engine
        return Button { store.transcriptionEngine = engine } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? look.palette.accent : look.palette.inkTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(look.type.callout.weight(.semibold)).foregroundStyle(look.palette.ink)
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .notDownloaded(let size):
                Text("Not downloaded · \(Self.size(size))").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                Text("Until it’s downloaded, Apple’s recognizer transcribes.")
                    .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                Button("Download \(Self.size(size))") { model.start() }.buttonStyle(.look(.secondary))
                cellularToggle
            case .downloading(let fraction, let speed):
                let total = SpeechModelConfiguration.sizeBytes
                if look.id == .midnight { MidnightProgressBar(value: fraction, width: 20) } else { ProgressTrack(value: fraction) }
                Text("\(Self.size(Int64(fraction * Double(total)))) of \(Self.size(total))\(speed > 0 ? " · \(Self.size(Int64(speed)))/s" : "")")
                    .font(look.type.caption.monospacedDigit())
                    .foregroundStyle(look.palette.inkSecondary)
                if model.isOnCellular && !model.allowCellular {
                    Text("Waiting for Wi‑Fi.").font(look.type.caption).foregroundStyle(look.palette.caution)
                }
                HStack(spacing: 16) {
                    Button("Pause") { model.pause() }
                    Button("Cancel", role: .destructive) { model.cancel() }
                }
                .font(look.type.callout.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(look.palette.inkSecondary)
            case .paused:
                Text("Paused").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                HStack(spacing: 16) {
                    Button("Resume") { model.start() }.buttonStyle(.look(.secondary))
                    Button("Cancel", role: .destructive) { model.cancel() }.buttonStyle(.look(.quiet))
                }
                cellularToggle
            case .ready(let size):
                Label("Ready · \(Self.size(size)) on this iPhone", systemImage: "checkmark.circle")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.positive)
                Button("Delete the model", role: .destructive) { model.delete() }.buttonStyle(.look(.quiet))
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.record)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.start() }.buttonStyle(.look(.secondary))
            }
        }
    }

    private var cellularToggle: some View {
        Toggle(isOn: Binding(get: { model.allowCellular }, set: { model.allowCellular = $0 })) {
            Text("Use cellular data").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
        }
        .tint(look.palette.accent)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

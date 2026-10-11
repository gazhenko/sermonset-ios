import SermonSetCore
import SwiftUI
import UniformTypeIdentifiers

/// A full copy of the library (audio included) saved wherever Files can reach: iCloud Drive,
/// Google Drive, Dropbox, or a drive. Restoring merges without duplicates.
struct BackupSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @State private var backup: BackupController?
    @State private var protect = false
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var exportURL: URL?
    @State private var showingMover = false
    @State private var showingImporter = false
    @State private var restoreURL: URL?
    @State private var restorePassphrase = ""
    @State private var message: String?

    private var passphraseOK: Bool { !protect || (passphrase.count >= 8 && passphrase == confirm) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Back up to Files").font(look.type.headline).foregroundStyle(look.palette.ink)
            Text("Saves your whole library, including recordings, notes, and moments, as one file. Put it in iCloud Drive, Google Drive, Dropbox, or anywhere the Files app reaches.")
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Protect with a passphrase", isOn: $protect).tint(look.palette.accent)
                .font(look.type.body).foregroundStyle(look.palette.ink)
            if protect {
                SecureField("Passphrase (8 or more characters)", text: $passphrase)
                    .textContentType(.newPassword)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                SecureField("Type it again", text: $confirm)
                    .textContentType(.newPassword)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                Text("There’s no way to recover a forgotten passphrase.")
                    .font(look.type.caption).foregroundStyle(look.palette.caution)
            }

            switch backup?.state ?? .idle {
            case .running:
                HStack(spacing: 8) {
                    ProgressView().tint(look.palette.accent)
                    Text("Working…").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                }
            default:
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await backup?.export(passphrase: protect ? passphrase : nil)
                            if let url = backup?.exportedURL { exportURL = url; showingMover = true }
                        }
                    } label: { Label("Back up now", systemImage: "externaldrive.badge.icloud") }
                    .buttonStyle(.look(.primary))
                    .disabled(!passphraseOK)
                    Button("Restore…") { showingImporter = true }
                        .buttonStyle(.look(.secondary))
                }
            }
            if case .failed(let message) = backup?.state ?? .idle {
                Text(message).font(look.type.caption).foregroundStyle(look.palette.record)
            }
            if let message {
                Label(message, systemImage: "checkmark.circle").font(look.type.callout).foregroundStyle(look.palette.positive)
            }
            if restoreURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This backup is protected. Enter its passphrase.").font(look.type.callout).foregroundStyle(look.palette.ink)
                    SecureField("Passphrase", text: $restorePassphrase)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                    HStack {
                        Button("Restore") { Task { await restore(passphrase: restorePassphrase) } }.buttonStyle(.look(.primary))
                        Button("Cancel") { restoreURL = nil; restorePassphrase = "" }.buttonStyle(.look(.quiet))
                    }
                }
            }
        }
        .onAppear { if backup == nil { backup = BackupController(store: store) } }
        .fileMover(isPresented: $showingMover, file: exportURL) { result in
            if case .success = result { message = "Backup saved." }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.zip, .data]) { result in
            guard case .success(let url) = result else { return }
            if url.pathExtension.lowercased() == "ssbackup" {
                restoreURL = url
            } else {
                restoreURL = nil
                Task { await restore(from: url, passphrase: nil) }
            }
        }
    }

    private func restore(passphrase: String) async {
        guard let url = restoreURL else { return }
        await restore(from: url, passphrase: passphrase)
    }

    private func restore(from url: URL, passphrase: String?) async {
        message = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        await backup?.restore(from: url, passphrase: passphrase)
        if let result = backup?.restoreResult {
            restoreURL = nil
            restorePassphrase = ""
            message = result.addedSermons == 0
                ? "Everything in that backup is already here."
                : "Restored \(result.addedSermons) \(result.addedSermons == 1 ? "sermon" : "sermons")\(result.skippedSermons > 0 ? "; \(result.skippedSermons) were already here" : "")."
        }
    }
}

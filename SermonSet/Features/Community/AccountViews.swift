import SermonSetCore
import SwiftUI
import UniformTypeIdentifiers

/// The Settings entry for the optional community account.
struct CommunityAccountSection: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @State private var joining = false
    @State private var restoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Community", detail: "Optional. Trading, sharing, and the real Sunday Pack need it.")
            if let account = community.account {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(style: account.avatarStyle, name: account.displayName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName ?? "No name").font(look.type.headline).foregroundStyle(look.palette.ink)
                            Text("Profile, recovery kit, and linked browsers").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(look.palette.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .lookPanel(padding: 14)
                .accessibilityIdentifier("settings.account")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    JoinPromises()
                    Button("Create a community account") { joining = true }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .accessibilityIdentifier("settings.join")
                    Button("Restore from a recovery kit") { restoring = true }
                        .buttonStyle(.look(.quiet, fullWidth: true))
                }
                .lookPanel(padding: 16)
            }
        }
        .sheet(isPresented: $joining) { JoinCommunitySheet().lookScoped(look) }
        .sheet(isPresented: $restoring) { RestoreAccountSheet().lookScoped(look) }
    }
}

struct JoinPromises: View {
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            promise("key", "No email or password. A private key on this iPhone is your account.")
            promise("lock", "Recordings, notes, moments, and transcripts never leave this iPhone because you joined.")
            promise("person.crop.circle.badge.questionmark", "Your name is optional and only shown to people you trade with.")
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(look.type.callout).foregroundStyle(look.palette.ink).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(look.palette.accent)
        }
    }
}

struct AvatarPicker: View {
    @Environment(\.look) private var look
    @Binding var style: String
    var name: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(AvatarStyle.allCases) { avatar in
                    Button { style = avatar.rawValue } label: {
                        AvatarView(style: avatar.rawValue, name: name, size: 48)
                            .padding(3)
                            .overlay(Circle().strokeBorder(style == avatar.rawValue ? look.palette.ink : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(avatar.name)
                    .accessibilityAddTraits(style == avatar.rawValue ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

struct JoinCommunitySheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    @State private var name = ""
    @State private var avatar = AvatarStyle.leaf.rawValue
    @State private var working = false
    @State private var error: String?
    @State private var created = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if created {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("You’re in", systemImage: "checkmark.circle.fill")
                                .font(look.type.title).foregroundStyle(look.palette.positive)
                            Text("Save a recovery kit next. It’s the only way to move this account to a new iPhone.")
                                .font(look.type.body).foregroundStyle(look.palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            RecoveryKitPanel()
                        }
                    } else {
                        Text("Join the community")
                            .font(look.type.hero).lookDisplay(look).foregroundStyle(look.palette.ink)
                        JoinPromises()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name (optional)").font(look.type.headline).foregroundStyle(look.palette.ink)
                            LookTextField(placeholder: "What people you trade with see", text: $name)
                            Text("Leave it empty to stay anonymous.").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Avatar").font(look.type.headline).foregroundStyle(look.palette.ink)
                            AvatarPicker(style: $avatar, name: name)
                        }
                        if let error {
                            Text(error).font(look.type.callout).foregroundStyle(look.palette.record).fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            Task { await create() }
                        } label: {
                            if working { ProgressView().tint(look.palette.onAccent) } else { Text("Create account") }
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .disabled(working)
                        .accessibilityIdentifier("join.create")
                    }
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: created ? .confirmationAction : .cancellationAction) {
                    Button(created ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() async {
        working = true
        error = nil
        defer { working = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await community.createAccount(displayName: trimmed.isEmpty ? nil : trimmed, avatarStyle: avatar)
            withAnimation { created = true }
        } catch {
            self.error = Self.message(error)
        }
    }

    static func message(_ error: Error) -> String {
        if error is URLError { return "Couldn’t reach the \(AppBrand.name) community. Check your connection and try again." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Export the passphrase-wrapped key as a file or a QR code.
struct RecoveryKitPanel: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var kitURL: URL?
    @State private var kitText: String?
    @State private var saving = false
    @State private var showingQR = false
    @State private var error: String?
    @State private var saved = false

    private var ready: Bool { passphrase.count >= 8 && passphrase == confirm }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery kit").font(look.type.headline).foregroundStyle(look.palette.ink)
            Text("Your account key, locked with a passphrase you choose. Anyone with both can use your account, so keep them apart.")
                .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Passphrase (8 or more characters)", text: $passphrase)
                .textContentType(.newPassword)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
            SecureField("Type it again", text: $confirm)
                .textContentType(.newPassword)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
            HStack(spacing: 10) {
                Button { export(thenQR: false) } label: { Label("Save to Files", systemImage: "folder") }
                    .buttonStyle(.look(.primary))
                Button { export(thenQR: true) } label: { Label("Show as QR", systemImage: "qrcode") }
                    .buttonStyle(.look(.secondary))
            }
            .disabled(!ready)
            if let error {
                Text(error).font(look.type.caption).foregroundStyle(look.palette.record)
            }
            if saved {
                Label("Recovery kit saved.", systemImage: "checkmark.circle").font(look.type.callout).foregroundStyle(look.palette.positive)
            }
        }
        .fileMover(isPresented: $saving, file: kitURL) { result in
            if case .success = result { saved = true }
        }
        .sheet(isPresented: $showingQR) {
            if let kitText {
                RecoveryQRSheet(text: kitText).lookScoped(look)
            }
        }
    }

    private func export(thenQR: Bool) {
        error = nil
        do {
            let url = try community.exportRecoveryKit(passphrase: passphrase)
            kitURL = url
            if thenQR {
                kitText = try String(contentsOf: url, encoding: .utf8)
                showingQR = true
            } else {
                saving = true
            }
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }
}

private struct RecoveryQRSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    var text: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                QRCodeImage(text: text, label: "Recovery kit QR code")
                    .frame(maxWidth: 320)
                Text("On your new iPhone, choose Restore from a recovery kit and scan this. You’ll need your passphrase too.")
                    .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Take a screenshot only if you store it somewhere private.")
                    .font(look.type.caption).foregroundStyle(look.palette.caution)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { LookBackground() }
            .navigationTitle("Recovery kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RestoreAccountSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    @State private var kitURL: URL?
    @State private var passphrase = ""
    @State private var picking = false
    @State private var scanning = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Restore your account")
                        .font(look.type.title).lookDisplay(look).foregroundStyle(look.palette.ink)
                    Text("Use the recovery kit you saved from your other iPhone, as a file or a QR code.")
                        .font(look.type.body).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button { picking = true } label: { Label("Choose file", systemImage: "folder") }
                            .buttonStyle(.look(.secondary))
                        Button { scanning = true } label: { Label("Scan QR", systemImage: "qrcode.viewfinder") }
                            .buttonStyle(.look(.secondary))
                    }
                    if let kitURL {
                        Label("Kit ready: \(kitURL.lastPathComponent)", systemImage: "doc.badge.ellipsis")
                            .font(look.type.callout).foregroundStyle(look.palette.ink)
                        SecureField("Passphrase", text: $passphrase)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                        Button {
                            Task { await restore(kitURL) }
                        } label: {
                            if working { ProgressView().tint(look.palette.onAccent) } else { Text("Restore account") }
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .disabled(passphrase.isEmpty || working)
                    }
                    if let error {
                        Text(error).font(look.type.callout).foregroundStyle(look.palette.record).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .json]) { result in
                if case .success(let url) = result { kitURL = url; error = nil }
            }
            .sheet(isPresented: $scanning) {
                QRScanSheet(title: "Scan recovery kit", hint: "Show the recovery kit QR on your other iPhone and point this camera at it.") { code in
                    guard code.contains("wrappedPrivateKey") else { return "That isn’t a \(AppBrand.name) recovery kit." }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scanned-\(UUID()).ssrecovery")
                    do { try Data(code.utf8).write(to: url, options: .completeFileProtection) } catch { return error.localizedDescription }
                    kitURL = url
                    return nil
                }
                .lookScoped(look)
            }
        }
    }

    private func restore(_ url: URL) async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await community.importRecoveryKit(from: url, passphrase: passphrase)
            dismiss()
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }
}

struct AccountView: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    @State private var name = ""
    @State private var avatar = AvatarStyle.plain.rawValue
    @State private var journeys = false
    @State private var journeyCity = ""
    @State private var hidePast = false
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let account = community.account {
                    profile(account)
                    journeysSection
                    RecoveryKitPanel().lookPanel(padding: 16)
                    LinkBrowserPanel(account: account).lookPanel(padding: 16)
                    AccountIDRow(id: account.id)
                    BlockedPeopleLink()
                    deleteSection
                }
            }
            .padding(20)
        }
        .background { LookBackground() }
        .navigationTitle("Community account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .confirmationDialog("Delete your community account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Your cards, offers, and shared sermons are removed from the server. Everything on this iPhone stays.")
        }
    }

    private func profile(_ account: CommunityAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(style: avatar, name: name, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Anonymous" : name).font(look.type.title).foregroundStyle(look.palette.ink)
                    Text(roleText(account)).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                }
            }
            LookTextField(placeholder: "Name (optional)", text: $name)
            AvatarPicker(style: $avatar, name: name)
            Button {
                Task { await save() }
            } label: {
                if saving { ProgressView().tint(look.palette.onAccent) } else { Text("Save profile") }
            }
            .buttonStyle(.look(.primary))
            .disabled(saving)
            if let message { Label(message, systemImage: "checkmark.circle").font(look.type.callout).foregroundStyle(look.palette.positive) }
            if let error { Text(error).font(look.type.callout).foregroundStyle(look.palette.record) }
        }
        .lookPanel(padding: 16)
    }

    private var journeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $journeys) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Card journeys").font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text("Add your city to the path a card travels when you trade it. Only shown when everyone on the path agreed, and only once at least three cards have passed through a city.")
                        .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(look.palette.accent)
            if journeys {
                LookTextField(placeholder: "Your city", text: $journeyCity)
                Toggle("Hide journeys I was part of before", isOn: $hidePast)
                    .font(look.type.callout).tint(look.palette.accent)
            }
            Button("Save journey settings") { Task { await save() } }
                .buttonStyle(.look(.secondary))
                .disabled(saving || (journeys && journeyCity.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .lookPanel(padding: 16)
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete community account", role: .destructive) { confirmDelete = true }
                .buttonStyle(.look(.destructive))
            Text("Your recordings and library on this iPhone aren’t affected.")
                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
        }
    }

    private func roleText(_ account: CommunityAccount) -> String {
        let roles = account.roles.map(\.role).filter { $0 != "listener" }
        if roles.contains("admin") { return "Admin" }
        if roles.contains("moderator") { return "Moderator" }
        if roles.contains("churchStaff") { return "Church staff" }
        return "Listener"
    }

    private func load() {
        guard let account = community.account else { return }
        name = account.displayName ?? ""
        avatar = account.avatarStyle
        journeys = account.journeyOptIn
        journeyCity = account.journeyCity ?? ""
    }

    private func save() async {
        saving = true
        message = nil
        error = nil
        defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = journeyCity.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await community.updateAccount(displayName: trimmed.isEmpty ? nil : trimmed, avatarStyle: avatar, journeyOptIn: journeys, journeyCity: journeys && !city.isEmpty ? city : nil, hidePastJourneys: hidePast)
            message = "Saved."
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }

    private func delete() async {
        do {
            try await community.deleteAccount()
            dismiss()
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }
}

/// A one-time code for signing in to the church portal or moderation console on a computer.
struct LinkBrowserPanel: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    var account: CommunityAccount
    @State private var code: BrowserLinkCode?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link a browser").font(look.type.headline).foregroundStyle(look.palette.ink)
            Text("For church staff and moderators. Open \(portalHost) on a computer and type the code. It works once and lasts five minutes.")
                .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let code, code.expiresAt > .now {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spaced(code.code))
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(look.palette.ink)
                            .textSelection(.enabled)
                            .accessibilityLabel("Code \(code.code.map(String.init).joined(separator: " "))")
                        let left = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
                        Text(left > 0 ? "Expires in \(left / 60):\(String(format: "%02d", left % 60))" : "Expired")
                            .font(look.type.caption.monospacedDigit())
                            .foregroundStyle(left > 30 ? look.palette.inkSecondary : look.palette.record)
                    }
                }
            }
            Button {
                Task { await makeCode() }
            } label: {
                if working { ProgressView() } else { Text(code == nil ? "Show a code" : "New code") }
            }
            .buttonStyle(.look(.secondary))
            .disabled(working)
            if let error { Text(error).font(look.type.caption).foregroundStyle(look.palette.record) }
        }
    }

    private var portalHost: String {
        let host = URL(string: community.configuration.audience)?.host() ?? "the web"
        return account.roles.contains { $0.role == "moderator" || $0.role == "admin" } ? "\(host)/moderate" : "\(host)/church"
    }

    /// Easier to read across a room: split in two halves.
    private func spaced(_ code: String) -> String {
        guard code.count >= 6 else { return code }
        let half = code.count / 2
        return String(code.prefix(half)) + " " + String(code.dropFirst(half))
    }

    private func makeCode() async {
        working = true
        error = nil
        defer { working = false }
        do { code = try await community.linkBrowser() } catch { self.error = JoinCommunitySheet.message(error) }
    }
}

struct BlockedPeopleLink: View {
    @Environment(\.look) private var look

    var body: some View {
        NavigationLink {
            BlockedPeopleView()
        } label: {
            HStack {
                Label("Blocked people", systemImage: "hand.raised")
                    .font(look.type.headline).foregroundStyle(look.palette.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(look.palette.inkTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lookPanel(padding: 14)
    }
}

/// The account ID, for church setup and support. It identifies the account but can't sign in to it.
struct AccountIDRow: View {
    @Environment(\.look) private var look
    var id: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Account ID").font(look.type.headline).foregroundStyle(look.palette.ink)
                Text(id)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(look.palette.inkSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = id
                copied = true
            }
            .font(look.type.callout.weight(.semibold))
            .foregroundStyle(look.palette.accent)
        }
        .lookPanel(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Account ID \(id)")
    }
}

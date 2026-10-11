import SermonSetCore
import SwiftUI

enum ReportTargetKind: String {
    case sermon, audio, card, account
}

enum ReportReasonChoice: String, CaseIterable, Identifiable {
    case rights, privacy, wrongAttribution, misleadingEdit, sensitiveContent, abuse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rights: "Shared without permission"
        case .privacy: "Private moment or person"
        case .wrongAttribution: "Wrong church or preacher"
        case .misleadingEdit: "Edited to mislead"
        case .sensitiveContent: "Sensitive content"
        case .abuse: "Abuse or impersonation"
        }
    }
    var detail: String {
        switch self {
        case .rights: "The church didn’t allow this audio to be shared."
        case .privacy: "It includes prayer requests, children, or a private conversation."
        case .wrongAttribution: "The title, preacher, church, or date is wrong."
        case .misleadingEdit: "Cut or arranged to change what was said."
        case .sensitiveContent: "Something people should be warned about."
        case .abuse: "Harassment, or someone pretending to be someone else."
        }
    }
}

/// Tell the moderators something is wrong. Reports are private; the person reported isn’t told who sent it.
struct ReportSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    var targetType: ReportTargetKind
    var targetID: String
    var targetName: String
    /// Seconds into the audio, when the problem is at a moment.
    var timestamp: TimeInterval?

    @State private var reason: ReportReasonChoice?
    @State private var details = ""
    @State private var includeTime = true
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sent {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Report sent", systemImage: "checkmark.circle.fill")
                                .font(look.type.title).foregroundStyle(look.palette.positive)
                            Text("A moderator will look at it. You’ll see the outcome in your inbox. The person you reported isn’t told who sent it.")
                                .font(look.type.body).foregroundStyle(look.palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("What’s wrong with “\(targetName)”?")
                            .font(look.type.title)
                            .foregroundStyle(look.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            ForEach(ReportReasonChoice.allCases) { choice in
                                Button { reason = choice } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: reason == choice ? "largecircle.fill.circle" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(reason == choice ? look.palette.accent : look.palette.inkTertiary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(choice.title).font(look.type.headline).foregroundStyle(look.palette.ink)
                                            Text(choice.detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(reason == choice ? [.isSelected, .isButton] : .isButton)
                            }
                        }
                        .lookPanel(padding: 4)
                        if let timestamp {
                            Toggle("Point to \(Format.clock(timestamp)) in the audio", isOn: $includeTime)
                                .font(look.type.callout).tint(look.palette.accent)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Anything else? (optional)").font(look.type.headline).foregroundStyle(look.palette.ink)
                            TextField("Details help moderators act faster", text: $details, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                        }
                        if let error {
                            Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                        }
                        Button {
                            Task { await send() }
                        } label: {
                            if sending { ProgressView().tint(look.palette.onAccent) } else { Text("Send report") }
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .disabled(reason == nil || sending)
                    }
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: sent ? .confirmationAction : .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        guard let reason else { return }
        sending = true
        error = nil
        defer { sending = false }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await community.report(
                target: ReportTarget(rawValue: targetType.rawValue) ?? .sermon,
                targetID: targetID,
                reason: ReportReason(rawValue: reason.rawValue) ?? .rights,
                timestamp: includeTime ? timestamp : nil,
                details: trimmed.isEmpty ? nil : trimmed
            )
            withAnimation { sent = true }
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }
}

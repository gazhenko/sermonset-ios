import SermonSetCore
import SwiftUI

/// Everything the community sent the listener: offers, trade results, and decisions about what they shared.
struct InboxView: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ZStack {
                LookBackground()
                if community.inbox.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "tray")
                    } description: {
                        Text("Offers, finished trades, and news about sermons you shared will show up here.")
                    }
                    .foregroundStyle(look.palette.ink)
                } else {
                    List {
                        ForEach(community.inbox.sorted { $0.createdAt > $1.createdAt }) { item in
                            Button { open(item) } label: { InboxRow(item: item) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(look.palette.rule)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if community.inbox.contains(where: { !$0.read }) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Mark all read") {
                            let unread = community.inbox.filter { !$0.read }
                            Task { for item in unread { try? await community.markInboxRead(item.id) } }
                        }
                    }
                }
            }
            .refreshable { await community.refresh() }
            .safeAreaInset(edge: .top) {
                CommunityStatusNote { await community.refresh() }.padding(.horizontal, 16)
            }
        }
    }

    private func open(_ item: InboxItem) {
        if !item.read { Task { try? await community.markInboxRead(item.id) } }
        if item.type.hasPrefix("offer") {
            dismiss()
            router.openOffer(id: item.resourceID)
        }
    }
}

private struct InboxRow: View {
    @Environment(\.look) private var look
    var item: InboxItem

    var body: some View {
        let copy = InboxCopy(item.type)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: copy.symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(look.palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.title)
                    .font(item.read ? look.type.body : look.type.headline)
                    .foregroundStyle(look.palette.ink)
                Text(copy.detail)
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)
            }
            Spacer(minLength: 0)
            if !item.read {
                Circle().fill(look.palette.record).frame(width: 9, height: 9).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.read ? "" : "New. ")\(copy.title). \(copy.detail)")
    }
}

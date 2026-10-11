import SermonSetCore
import SwiftUI

/// The bell every tab shows once the listener has a community account.
struct InboxToolbarButton: View {
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    @Environment(\.look) private var look

    var body: some View {
        if community.account != nil {
            let unread = community.inbox.filter { !$0.read }.count
            Button { router.isInboxPresented = true } label: {
                Image(systemName: unread > 0 ? "bell.badge" : "bell")
                    .symbolRenderingMode(unread > 0 ? .palette : .monochrome)
                    .foregroundStyle(look.palette.record, look.palette.ink)
            }
            .accessibilityLabel(unread > 0 ? "Inbox, \(unread) new" : "Inbox")
            .accessibilityIdentifier("toolbar.inbox")
        }
    }
}

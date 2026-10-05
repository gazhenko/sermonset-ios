import SermonSetCore
import SwiftUI

/// Shows the store's latest error from inside a sheet or full-screen cover, where the root
/// view's alert can't appear.
struct StoreErrorAlert: ViewModifier {
    @Environment(SermonStore.self) private var store

    func body(content: Content) -> some View {
        content.alert(
            store.lastError?.title ?? "Something went wrong",
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.clearError() } }),
            presenting: store.lastError
        ) { _ in
            Button("OK") { store.clearError() }
        } message: { error in
            Text([error.message, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }
}

extension View {
    func storeErrorAlert() -> some View {
        modifier(StoreErrorAlert())
    }
}

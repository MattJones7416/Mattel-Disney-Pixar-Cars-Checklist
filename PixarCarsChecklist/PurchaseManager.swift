import SwiftUI

/// Keeps the source app's feature-gating interface while making every collector
/// feature available in this first Cars release.
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var isUnlocked = true
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private init() {}

    func purchase() async -> Bool { true }
    func restore() async { isUnlocked = true }
    func refreshProducts() async {}
    func setUnlocked(_ unlocked: Bool) { isUnlocked = true }
}

struct UnlockSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Everything Is Included",
                systemImage: "checkmark.seal.fill",
                description: Text("Collection quantities, favourites, wishlist, photos, notes and developer tools are all available.")
            )
            .navigationTitle("Collector Features")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingUnlockSheet = false
    @Binding var selectedTab: ContentView.Tab
    @Binding var selectedModel: MetalModel?
    var sourceModels: [MetalModel]?
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    private var models: [MetalModel] {
        sourceModels ?? dataManager.favoriteModels
    }

    var body: some View {
        ZStack {
            ModelBrowserView(
                title: "Favorites",
                sourceModels: models,
                emptyTitle: "No favorites yet",
                emptySubtitle: "Tap the star on a model to add it here.",
                storagePrefix: "favorites",
                selectedModel: $selectedModel,
                readOnly: readOnly,
                onCollectionChanged: onCollectionChanged
            )
            .environmentObject(dataManager)

            if !readOnly && !purchaseManager.isUnlocked {
                Color.black.opacity(0.08).ignoresSafeArea()
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "lock")
                                .font(.title2)
                                .foregroundColor(Color.gray.opacity(0.8))
                                .padding(12)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                            Text("Favorites are part of Premium")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Unlock") {
                                showingUnlockSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingUnlockSheet) {
            UnlockSheet().environmentObject(purchaseManager)
        }
    }
}

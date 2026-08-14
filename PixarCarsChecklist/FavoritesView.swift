import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingUnlockSheet = false
    @Binding var selectedTab: ContentView.Tab
    @Binding var selectedModel: MetalModel?

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = Debouncer(delay: 0.3)
    @AppStorage("favoritesSortOption") private var sortOption = "name"

    private var favoriteModels: [MetalModel] {
        var models = dataManager.allModels.filter { $0.isFavorite }

        if !debouncedSearchText.isEmpty {
            models = models.filter { $0.matches(debouncedSearchText) }
        }

        switch sortOption {
        case "name":
            return models.sorted { $0.name < $1.name }
        case "number":
            return models.sorted { $0.productCode.localizedStandardCompare($1.productCode) == .orderedAscending }
        case "year", "difficulty":
            return models.sorted { ($0.firstReleaseYear ?? 9999) < ($1.firstReleaseYear ?? 9999) }
        default:
            return models
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: searchText) { _, newValue in
                        searchDebouncer.run {
                            debouncedSearchText = newValue
                        }
                    }

                HStack {
                    Text("\(favoriteModels.count) Favorites")
                        .font(.headline)
                        .padding(.leading)

                    Spacer()

                    Menu {
                        Button("Sort by Name") { sortOption = "name" }
                        Button("Sort by Product Code") { sortOption = "number" }
                        Button("Sort by First Release") { sortOption = "year" }
                    } label: {
                        HStack {
                            Text("Sort")
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 8)

                List(favoriteModels, id: \.id) { model in
                    Button {
                        if purchaseManager.isUnlocked {
                            selectedModel = model
                        } else {
                            // show unlock sheet
                            showingUnlockSheet = true
                        }
                    } label: {
                        ModelRowView(
                            model: model,
                            accentColor: Color(hex: "D92D20"),
                            compact: false,
                            dataManager: dataManager
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(
                        model.checked ? Color(hex: "D92D20").opacity(0.1) : Color.clear
                    )
                    .disabled(!purchaseManager.isUnlocked) // prevents tapping if locked
                }
                .listStyle(.plain)
            }
            .navigationTitle("Favorites")

            // Lock overlay (subtle) shown when locked
            if !purchaseManager.isUnlocked {
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

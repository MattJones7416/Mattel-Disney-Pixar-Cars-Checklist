import SwiftUI
import SwiftData


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#if os(iOS)
import UIKit
typealias MEPlatformImage = UIImage
#else
import AppKit
typealias MEPlatformImage = NSImage
#endif

/// Robust bundle loader: tries asset catalog name (no ext), then path(forResource:)
func loadBundleImage(named assetName: String) -> MEPlatformImage? {
    let ns = (assetName as NSString)
    let resource = ns.deletingPathExtension    // e.g. "MEM042G_Gold Marvin the Martian"
    let ext = ns.pathExtension.lowercased()   // e.g. "png"

    // 1) Try asset-catalog style (name without extension)
    #if os(iOS)
    if let img = UIImage(named: resource) { return img }
    #else
    if let img = NSImage(named: NSImage.Name(resource)) { return img }
    #endif

    // 2) Try the specific extension or common extensions using Bundle path
    let exts = ext.isEmpty ? ["png", "jpg", "jpeg"] : [ext]
    for e in exts {
        if let path = Bundle.main.path(forResource: resource, ofType: e) {
            #if os(iOS)
            if let ui = UIImage(contentsOfFile: path) { return ui }
            #else
            if let nsImg = NSImage(contentsOfFile: path) { return nsImg }
            #endif
        }
    }

    // 3) Try replacing spaces with underscores (common mismatch)
    let altResource = resource.replacingOccurrences(of: " ", with: "_")
    for e in exts {
        if let path = Bundle.main.path(forResource: altResource, ofType: e) {
            #if os(iOS)
            if let ui = UIImage(contentsOfFile: path) { return ui }
            #else
            if let nsImg = NSImage(contentsOfFile: path) { return nsImg }
            #endif
        }
    }

    return nil
}

// Simple remote loader using StateObject (correct wrapper usage)
final class MEImageLoader: ObservableObject {
    @Published var image: MEPlatformImage? = nil
    private var task: URLSessionDataTask?
    private let urlString: String?

    init(urlString: String?) {
        self.urlString = urlString
        load()
    }
    deinit { task?.cancel() }

    func load() {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        struct Cache { static var images: [String: MEPlatformImage] = [:] }
        if let cached = Cache.images[urlString] {
            self.image = cached
            return
        }

        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        task = URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else { return }
            #if os(iOS)
            if let ui = UIImage(data: data) {
                DispatchQueue.main.async {
                    Cache.images[urlString] = ui
                    self.image = ui
                }
            }
            #else
            if let ns = NSImage(data: data) {
                DispatchQueue.main.async {
                    Cache.images[urlString] = ns
                    self.image = ns
                }
            }
            #endif
        }
        task?.resume()
    }
}

struct MERemoteImage: View {
    @StateObject private var loader: MEImageLoader

    init(urlString: String?) {
        _loader = StateObject(wrappedValue: MEImageLoader(urlString: urlString))
    }

    var body: some View {
        Group {
            if let img = loader.image {
                #if os(iOS)
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                #else
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                #endif
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }
}



#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingUnlockSheet = false
    @State private var expandedCategories: Set<String> = []
    @State private var searchText = ""
    @State private var debouncedSearchText = "" // Add this line
    @State private var searchDebouncer = Debouncer(delay: 0.3) // Add this line (0.5 second delay)
    @AppStorage("showCollected") private var showCollected = true
    @AppStorage("showUncollected") private var showUncollected = true
    @AppStorage("showBuilt") private var showBuilt = true
    @AppStorage("showUnbuilt") private var showUnbuilt = true
    @AppStorage("sortOption") private var sortOption = "name"
    @AppStorage("viewMode") private var viewMode = "categories"
    @AppStorage("selectedType") private var selectedType = "All"
    @State private var hiddenCategories: Set<String> = []
    @State private var selectedTab: Tab = .list
    @State private var selectedModel: MetalModel? = nil

    @AppStorage("showComingSoon") private var showComingSoon = true
    @AppStorage("showExclusive") private var showExclusive = true
    @AppStorage("showRetired") private var showRetired = true
    @AppStorage("showNormal") private var showNormal = true

    @AppStorage("showImageGrid") private var showImageGrid = false

    @AppStorage("devModeEnabled") private var devModeEnabled: Bool = false

    let accentColor = Color(hex: "D92D20")

    enum Tab {
        case list
        case gallery
        case favorites
        case wishlist
        case settings
    }

    // Mac-only: no bottom padding for content (iPhone keeps 60)
    private var bottomBarPadding: CGFloat {
        #if os(iOS)
        return 60
        #else
        return 0
        #endif
    }


    private var allTypes: [String] {
        let preferred = ["1:55 Die-Cast", "Mini Racers", "Collector Exclusive", "Special Edition", "Premium / Larger Scale"]
        let available = Set(dataManager.allModels.map(\.type).filter { !$0.isEmpty })
        return ["All"] + preferred.filter { available.contains($0) }
    }

    private var typeScopedCategories: [String] {
        // Categories visible for the currently selected release line.
        var base = dataManager.allModels

        if selectedType != "All" {
            base = base.filter { $0.type == selectedType }
        }

        let cats = Set(base.map { $0.category })
        return cats.sorted()
    }

    private var collectionStats: (collected: Int, total: Int) {
        let total = filteredModels.count
        let collected = filteredModels.filter { $0.checked }.count
        return (collected, total)
    }

    private var filteredModels: [MetalModel] {
        var result = dataManager.allModels

        // Apply type filter
        if selectedType != "All" {
            result = result.filter { $0.type == selectedType }
        }

        // Apply search filter - change searchText to debouncedSearchText here
        // Optimize search filtering
        if !debouncedSearchText.isEmpty {
            let searchText = debouncedSearchText.lowercased()
            result = result.filter { $0.matches(searchText) }
        }

        // Apply collection filters
        if !showCollected {
            result = result.filter { !$0.checked }
        }
        if !showUncollected {
            result = result.filter { $0.checked }
        }

        // Apply built/unbuilt filters
        if !showBuilt {
            result = result.filter { !$0.built }
        }
        if !showUnbuilt {
            result = result.filter { $0.built }
        }

        // Apply status filters
        result = result.filter { model in
            let status = model.status   // "Coming Soon", "Exclusive", "Retired", or empty/other
            return
                (showComingSoon && status == "Coming Soon") ||
                (showExclusive && status == "Exclusive") ||
                (showRetired && status == "Retired") ||
                (showNormal && !["Coming Soon", "Exclusive", "Retired"].contains(status))
        }

        // Apply category visibility filters
        if !hiddenCategories.isEmpty {
            result = result.filter { !hiddenCategories.contains($0.category) }
        }

        // Apply sorting
        switch sortOption {
        case "name":
            return result.sorted { $0.name < $1.name }
        case "number":
            return result.sorted { $0.productCode.localizedStandardCompare($1.productCode) == .orderedAscending }
        case "year", "difficulty":
            return result.sorted { ($0.firstReleaseYear ?? 9999) < ($1.firstReleaseYear ?? 9999) }
        case "releases":
            return result.sorted { $0.releaseCount > $1.releaseCount }
        default:
            return result
        }
    }

    private func getCategorizedModels() -> [String: [MetalModel]] {
        Dictionary(grouping: filteredModels, by: { $0.category })
    }

    private func shouldExpandCategory(_ category: String) -> Bool {
        // Always expand if we're searching and this category has results
        if !searchText.isEmpty {
            return (getCategorizedModels()[category]?.isEmpty == false)
        }
        // Otherwise respect the user's expanded/collapsed preference
        return expandedCategories.contains(category)
    }

    private func isCategoryComplete(_ category: String) -> Bool {
        guard let models = getCategorizedModels()[category] else { return false }
        return !models.isEmpty && models.allSatisfy { $0.checked }
    }

    // MARK: - Expand / Collapse helpers
    private func expandAllCategories() {
        // Make sure to animate UI changes
        withAnimation {
            let cats = getCategorizedModels().keys
            expandedCategories.formUnion(cats)
        }
    }

    private func collapseAllCategories() {
        withAnimation {
            expandedCategories.removeAll()
        }
    }

    var body: some View {
        NavigationStack {
            // Main content area - switches between views based on selected tab
            Group {
                switch selectedTab {
                case .list:
                    VStack(spacing: 0) {
                        SearchBar(text: $searchText)
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .onChange(of: searchText) { oldValue, newValue in
                                searchDebouncer.run {
                                    debouncedSearchText = newValue
                                    // Automatically expand categories with matches when searching
                                    if !newValue.isEmpty {
                                        let matchingCategories = getCategorizedModels()
                                            .filter { !$0.value.isEmpty }
                                            .keys
                                        expandedCategories.formUnion(matchingCategories)
                                    }
                                }
                            }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allTypes, id: \.self) { type in
                                    Button(action: { selectedType = type }) {
                                        Text(type)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Group {
                                                    if selectedType == type {
                                                        accentColor.opacity(0.2)
                                                    } else {
                                                        Color.gray.opacity(0.12)
                                                    }
                                                }
                                            )
                                            .foregroundColor(selectedType == type ? accentColor : .primary)
                                            .cornerRadius(16)
                                    }
    #if os(macOS) || targetEnvironment(macCatalyst)
                                    .buttonStyle(.plain)
    #endif
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)

                        // Removed duplicate Model Type picker

                        VStack(spacing: 10) {
                            CollectionStatsView(
                                collected: collectionStats.collected,
                                total: collectionStats.total,
                                accentColor: accentColor
                            )
                            .padding(.top, 8)
                            // Row 2: Filters + Sort + View mode + Expand/Collapse
                            HStack(spacing: 8) {
                                // Filters Menu
                                Menu {
                                    Toggle("Show Collected", isOn: $showCollected)
                                    Toggle("Show Uncollected", isOn: $showUncollected)
                                    Toggle("Show Unboxed", isOn: $showBuilt)
                                    Toggle("Show Carded / Not Set", isOn: $showUnbuilt)
                                    Divider()
                                    Toggle("Show Standard Releases", isOn: $showNormal)
                                    Toggle("Show Exclusives", isOn: $showExclusive)
                                    Divider()
                                    Menu("Categories") {
                                        ForEach(typeScopedCategories, id: \.self) { cat in
                                            Toggle(cat, isOn: Binding<Bool>(
                                                get: { !hiddenCategories.contains(cat) },
                                                set: { newValue in
                                                    if newValue {
                                                        hiddenCategories.remove(cat)
                                                    } else {
                                                        hiddenCategories.insert(cat)
                                                    }
                                                }
                                            ))
                                        }
                                        Button("Show All Categories") { hiddenCategories.removeAll() }
                                    }
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 16))
                                        .padding(8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                }

#if os(macOS) || targetEnvironment(macCatalyst)
                                .buttonStyle(.plain)
#endif

                                // Expand / Collapse Toggle
                                if viewMode == "categories" {
                                    Button(action: {
                                        let visibleCategories = Array(getCategorizedModels().keys)
                                        let visibleSet = Set(visibleCategories)
                                        let expandedVisibleCount = expandedCategories.intersection(visibleSet).count

                                        withAnimation {
                                            if expandedVisibleCount == visibleCategories.count {
                                                expandedCategories.subtract(visibleSet)
                                            } else {
                                                expandedCategories.formUnion(visibleSet)
                                            }
                                        }
                                    }) {
                                        let visibleCategories = Array(getCategorizedModels().keys)
                                        let visibleSet = Set(visibleCategories)
                                        let allVisibleExpanded = expandedCategories.intersection(visibleSet).count == visibleCategories.count

                                        Image(systemName: allVisibleExpanded ? "arrow.up.to.line" : "arrow.down.to.line")
                                            .font(.system(size: 16))
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                            #if os(macOS) || targetEnvironment(macCatalyst)
                                    .buttonStyle(.plain)
                            #endif
                                }


                                // Sort Menu
                                Menu {
                                    Button("Sort by Name") { sortOption = "name" }
                                    Button("Sort by Product Code") { sortOption = "number" }
                                    Button("Sort by First Release") { sortOption = "year" }
                                    Button("Sort by Release Count") { sortOption = "releases" }
                                } label: {
                                    Label("Sort", systemImage: "arrow.up.arrow.down")
                                        .padding(8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                }
#if os(macOS) || targetEnvironment(macCatalyst)
                                .buttonStyle(.plain)
#endif

                                Button(action: {
                                    showImageGrid.toggle()
                                }) {
                                    Label(showImageGrid ? "List" : "Image",
                                          systemImage: showImageGrid ? "list.bullet" : "rectangle.grid.2x2")
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
#if os(macOS) || targetEnvironment(macCatalyst)
                                .buttonStyle(.plain)
#endif

                                // View mode toggle
                                Button(action: {
                                    viewMode = viewMode == "categories" ? "list" : "categories"
                                }) {
                                    Label(viewMode == "categories" ? "Unsorted" : "Sorted",
                                          systemImage: viewMode == "categories" ? "list.bullet" : "rectangle.grid.1x2")
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
#if os(macOS) || targetEnvironment(macCatalyst)
                                .buttonStyle(.plain)
#endif
                            }
                            .font(.caption)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }


                        if viewMode == "categories" {
                            if showImageGrid {
                                CategoryGridView(
                                    categorizedModels: getCategorizedModels(),
                                    expandedCategories: $expandedCategories,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel
                                )
                                .padding(.bottom, bottomBarPadding)
                            } else {
                                CategoryListView(
                                    categorizedModels: getCategorizedModels(),
                                    expandedCategories: $expandedCategories,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel
                                )
                                .padding(.bottom, bottomBarPadding)
                            }
                        } else {
                            if showImageGrid {
                                PlainGridView(
                                    models: filteredModels,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel
                                )
                                .padding(.bottom, bottomBarPadding)
                            } else {
                                PlainListView(
                                    models: filteredModels,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel
                                )
                                .padding(.bottom, bottomBarPadding)
                            }
                        }
                    }

                case .gallery:
                    PhotoGalleryView(
                        dataManager: dataManager,
                        selectedTab: $selectedTab,
                        selectedModel: $selectedModel
                    )
                    .padding(.bottom, bottomBarPadding)

                case .favorites:
                    FavoritesView(
                        selectedTab: $selectedTab,
                        selectedModel: $selectedModel
                    )
                    .environmentObject(dataManager)
                    .padding(.bottom, bottomBarPadding)

                case .wishlist:
                    WishlistView(
                        selectedTab: $selectedTab,
                        selectedModel: $selectedModel
                    )
                    .environmentObject(dataManager)
                    .padding(.bottom, bottomBarPadding)

                case .settings:
                    SettingsView()
                        .environmentObject(dataManager)
                        .padding(.bottom, bottomBarPadding)
                }
            }
#if os(iOS) || targetEnvironment(macCatalyst)
.navigationTitle("Pixar Cars Checklist")
.navigationBarTitleDisplayMode(.inline)
#else
.navigationTitle("Pixar Cars Checklist")
#endif

.navigationDestination(item: $selectedModel) { model in
    ModelDetailView(model: model, dataManager: dataManager)
}

.toolbar {
    #if os(iOS) || targetEnvironment(macCatalyst)
    ToolbarItem(placement: .principal) {
        Image("CarsChecklistLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 34)
            .accessibilityLabel("Pixar Cars Checklist")
    }
    #else
    // On macOS, put it in the standard window toolbar/title area
    ToolbarItem(placement: .automatic) {
        Image("CarsChecklistLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 34)
            .accessibilityLabel("Pixar Cars Checklist")
    }
    #endif
}

        }
        .sheet(isPresented: $showingUnlockSheet) {
            UnlockSheet().environmentObject(purchaseManager)
        }
        .accentColor(accentColor)
        .safeAreaInset(edge: .bottom) {
            // Your existing tab bar implementation
            VStack(spacing: 0) {
                Divider()
                HStack {
                    // List Button
                    Spacer()
                    Button(action: {
                        selectedTab = .list
                        selectedModel = nil
                    }) {
                        VStack {
                            Image(systemName: "list.bullet")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("List")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == .list ? accentColor : .gray)
                    }
#if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain) // no dark AppKit button chrome
#endif
                    Spacer()

                    // Gallery Button
                    Button(action: {
                        if purchaseManager.isUnlocked {
                            selectedTab = .gallery
                            selectedModel = nil
                        } else {
                            showingUnlockSheet = true
                        }
                    }) {
                        VStack {
                            Image(systemName: "camera")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Gallery")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == .gallery ? accentColor : .gray)
                        .overlay(
                            Group {
                                if !purchaseManager.isUnlocked {
                                    Image(systemName: "lock")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color.gray.opacity(0.75))
                                        .padding(6)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .offset(x: 12, y: -12)
                                }
                            }, alignment: .topTrailing
                        )
                    }


#if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain) // no dark AppKit button chrome
#endif
                    Spacer()

                    // Favorites Button
                    Button(action: {
                        if purchaseManager.isUnlocked {
                            selectedTab = .favorites
                            selectedModel = nil
                        } else {
                            showingUnlockSheet = true
                        }
                    }) {
                        VStack {
                            Image(systemName: "star")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Favorites")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == .favorites ? accentColor : .gray)
                        .overlay(
                            Group {
                                if !purchaseManager.isUnlocked {
                                    Image(systemName: "lock")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color.gray.opacity(0.75))
                                        .padding(6)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .offset(x: 12, y: -12)
                                }
                            }, alignment: .topTrailing
                        )
                    }

#if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain) // no dark AppKit button chrome
#endif
                    Spacer()

                    // Wishlist Button
                    Button(action: {
                        if purchaseManager.isUnlocked {
                            selectedTab = .wishlist
                            selectedModel = nil
                        } else {
                            showingUnlockSheet = true
                        }
                    }) {
                        VStack {
                            Image(systemName: "gift")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Wishlist")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == .wishlist ? accentColor : .gray)
                        .overlay(
                            Group {
                                if !purchaseManager.isUnlocked {
                                    Image(systemName: "lock")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color.gray.opacity(0.75))
                                        .padding(6)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .offset(x: 12, y: -12)
                                }
                            }, alignment: .topTrailing
                        )
                    }
#if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain)
#endif
                    Spacer()

                    // Settings Button
                    Button(action: {
                        selectedTab = .settings
                        selectedModel = nil
                    }) {
                        VStack {
                            Image(systemName: "gear")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Settings")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == .settings ? accentColor : .gray)
                    }
#if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain) // no dark AppKit button chrome
#endif
                    Spacer()
                }
                .padding(.top, 8)
                .background(.regularMaterial)
                .frame(height: 60)
            }
            .background(.regularMaterial)
        }
        .overlay(alignment: .top) {
            if devModeEnabled {
                DeveloperBanner(onOpenSettings: { selectedTab = .settings })
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }
}


struct CategoryListView: View {
    let categorizedModels: [String: [MetalModel]]
    @Binding var expandedCategories: Set<String>
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?

    private func isCategoryComplete(_ category: String) -> Bool {
        categorizedModels[category]?.allSatisfy { $0.checked } ?? false
    }

    var body: some View {
        List {
            ForEach(categorizedModels.keys.sorted(), id: \.self) { category in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { isExpanded in
                            withAnimation {
                                if isExpanded {
                                    expandedCategories.insert(category)
                                } else {
                                    expandedCategories.remove(category)
                                }
                            }
                        }
                    ),
                    content: {
                        ForEach(categorizedModels[category] ?? [], id: \.id) { model in
                            ModelRowView(
                                model: model,
                                accentColor: accentColor,
                                compact: false,
                                dataManager: dataManager
                            )
                            .padding(.leading, -16) // Add this line to reduce leading padding
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedModel = model
                            }
                            // ✅ collected rows highlighted (same as Favorites)
                            .listRowBackground(
                                model.checked ? accentColor.opacity(0.1) : Color.clear
                            )
                        }
                    },
                    label: {
                                            HStack {
                                                Text(category)
                                                    .font(.headline)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        withAnimation {
                                                            expandedCategories.toggle(category)
                                                        }
                                                    }

                                                Spacer()

                                                if isCategoryComplete(category) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(accentColor)
                                                }
                        }
                    }
                )
                .listRowBackground(
                    isCategoryComplete(category) ? accentColor.opacity(0.05) : Color.clear
                )
            }
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
}

struct PlainListView: View {
    let models: [MetalModel]
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?

    var body: some View {
        List(models, id: \.id) { model in
            Button {
                selectedModel = model
            } label: {
                ModelRowView(
                    model: model,
                    accentColor: accentColor,
                    compact: false,
                    dataManager: dataManager
                )
            }
            .buttonStyle(PlainButtonStyle())
            .listRowBackground(
                model.checked ? accentColor.opacity(0.1) : Color.clear
            )
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets())
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
#if os(iOS)
        UIApplication.shared.open(url)
#elseif os(macOS)
        NSWorkspace.shared.open(url)
#endif
    }
}


struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            TextField("Search cars, characters or product codes...", text: $text)
                .padding(8)
                .padding(.horizontal, 24)
                .background(searchBarBackgroundColor)
                .cornerRadius(8)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)

                        if !text.isEmpty {
                            Button(action: {
                                text = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .padding(.horizontal, 4)
        }
    }

    private var searchBarBackgroundColor: Color {
#if os(iOS)
        return Color(.systemGray6)
#else
        return Color(.windowBackgroundColor).opacity(0.7)
#endif
    }
}

struct CollectionStatsView: View {
    let collected: Int
    let total: Int
    let accentColor: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Collection Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(collected)/\(total) cars")
                    .font(.title2.bold())
            }

            Spacer()

            CircularProgressView(progress: total > 0 ? Double(collected)/Double(total) : 0,
                              accentColor: accentColor)
            .frame(width: 50, height: 50)
        }
        .padding()
        .background(platformBackgroundColor)
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private var platformBackgroundColor: Color {
#if os(iOS)
        return Color(.systemGroupedBackground)
#else
        return Color(.windowBackgroundColor)
#endif
    }
}

struct CircularProgressView: View {
    let progress: Double
    let accentColor: Color

    @State private var animatedProgress: Double = 0
    private let animationDelay: Double = 0.15
    private let animationDuration: Double = 0.35

    private var safeProgress: Double {
        if progress.isNaN || progress.isInfinite { return 0.0 }
        return min(max(progress, 0.0), 1.0)
    }

    private var percentageText: String {
        let percentage = safeProgress * 100
        if abs(percentage - percentage.rounded()) < 0.01 {
            return "\(Int(percentage.rounded()))%"
        }
        return "\(Int(percentage))%"
    }

    private func animateToCurrentProgress(withDelay: Bool) {
        let target = safeProgress
        let perform = {
            withAnimation(.linear(duration: animationDuration)) {
                animatedProgress = target
            }
        }
        if withDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay, execute: perform)
        } else {
            perform()
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 5)
                .opacity(0.3)
                .foregroundColor(.gray)

            Circle()
                .trim(from: 0, to: CGFloat(animatedProgress))
                .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .foregroundColor(accentColor)
                .rotationEffect(Angle(degrees: 270))

            Text(percentageText)
                .font(.caption)
        }
        .onAppear {
            animatedProgress = 0
            animateToCurrentProgress(withDelay: true)
        }
        .onChange(of: progress) { oldValue, newValue in
            animateToCurrentProgress(withDelay: true)
        }
    }
}

struct ModelRowView: View {
    let model: MetalModel
    let accentColor: Color
    var compact: Bool
    @ObservedObject var dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager

    var body: some View {
        HStack(spacing: 0) {
            // Left Group - First 3 icons flush left
            HStack(spacing: compact ? 4 : 8) {
                // 1. Favorite Star
                ZStack(alignment: .bottomTrailing) {
                    Button {
                        if purchaseManager.isUnlocked {
                            dataManager.toggleFavorite(for: model)
                        }
                    } label: {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .font(.system(size: compact ? 18 : 20))
                            .foregroundColor(model.isFavorite ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)

                    if !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }

                // 1b. Wishlist (gift)
                ZStack(alignment: .bottomTrailing) {
                    Button {
                        if purchaseManager.isUnlocked {
                            dataManager.toggleWishlist(for: model)
                        }
                    } label: {
                        Image(systemName: model.isWishlisted ? "gift.fill" : "gift")
                            .font(.system(size: compact ? 18 : 20))
                            .foregroundColor(model.isWishlisted ? .pink : .gray)
                    }
                    .buttonStyle(.plain)

                    if !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }


                // 2. Quantity
                ZStack(alignment: .bottomTrailing) {
                    Menu {
                        if purchaseManager.isUnlocked {
                            ForEach(0..<11, id: \.self) { quantity in
                                Button {
                                    dataManager.updateQuantity(for: model, quantity: quantity)
                                } label: {
                                    Text("\(quantity)")
                                }
                            }
                        }
                    } label: {
                        #if os(macOS)
                        Text(model.quantity > 0 ? "\(model.quantity)" : "0")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 24, height: 18)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                        #else
                        HStack(spacing: 2) {
                            if model.quantity > 0 {
                                Text("\(model.quantity)")
                                    .font(.subheadline)
                                    .padding(4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "number.square")
                                    .font(.system(size: compact ? 18 : 20))
                                    .foregroundColor(.gray)
                            }
                        }
                        #endif
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                    #endif

                    if !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }


                // 3. Checkbox
                if alwaysShowCheckbox {
                    Button {
                        dataManager.toggleChecked(for: model)
                    } label: {
                        Image(systemName: model.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: compact ? 18 : 22))
                            .foregroundColor(model.checked ? accentColor : .gray)
                    }
                    .buttonStyle(.plain)
                } else {
                    // iPhone/iPad behavior unchanged: only show when collected
                    if model.checked {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: compact ? 18 : 22))
                            .foregroundColor(accentColor)
                    }
                }
            }
            .padding(.leading, compact ? 1 : 2)

            Spacer()
                            .frame(width: 12) // Adjust this value to control the gap size

            // Middle Content
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                if !compact {
                    Text(model.productCode.isEmpty ? "First released \(model.firstReleaseYear.map { String($0) } ?? "—")" : model.productCode)
                        .font(.caption)
                        .foregroundColor(model.checked ? .primary : .secondary)
                }
                Text(model.name)
                    .font(compact ? .subheadline : .headline)
                    .foregroundColor(model.statusColor)
                    .lineLimit(1)
            }
            .id(model.id)
            .animation(nil, value: model.checked)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right Group - Icons flush right
            if !compact {
                HStack(spacing: 8) {
                    Group {
                        if model.built {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(.blue)
                                .accessibilityLabel("Unboxed")
                        }

                        if let year = model.firstReleaseYear {
                            Text(String(year))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: model.type == "Mini Racers" ? "car.side.fill" : "car.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(model.type)
                    }
                    .opacity(model.checked ? 1.0 : 0.7)

                    if !model.link.isEmpty {
                        Button(action: {
                            openURL(model.link)
                        }) {
                            Image(systemName: "link")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, compact ? 8 : 12)
            }
        }
        .padding(.vertical, compact ? 6 : 8)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                dataManager.toggleChecked(for: model)
            } label: {
                Label(model.checked ? "Mark Unchecked" : "Mark Checked",
                     systemImage: model.checked ? "square" : "checkmark.square.fill")
            }
            .tint(model.checked ? .gray : accentColor)
        }

        // Bottom controls (unchanged)
        // Inserted wishlist button after favorites button in ModelGridItemView per instructions

    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
    // Always show the checkbox when running on any Mac (Catalyst or iOS-on-Mac)
    private var alwaysShowCheckbox: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return true
        #else
        if #available(iOS 14.0, *) {
            // keep your old check AND add the iOS-on-Mac fallback
            return UIDevice.current.userInterfaceIdiom == .mac
                || ProcessInfo.processInfo.isiOSAppOnMac
        }
        return UIDevice.current.userInterfaceIdiom == .mac
        #endif
    }
}

// MARK: - Grid item & grid views

struct ModelGridItemView: View {
    let model: MetalModel
    let accentColor: Color
    let dataManager: DataManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    var onSelect: (() -> Void)? = nil

    // Config
    private let tileHeight: CGFloat = 170
    private let imageMaxHeight: CGFloat = 56
    private let horizontalPadding: CGFloat = 10

    // If productImage is an http URL return it; otherwise nil
    private var resolvedRemoteURL: String? {
        let prod = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prod.isEmpty else { return nil }
        return prod.lowercased().starts(with: "http") ? prod : nil
    }

    // Try to resolve a bundle image according to your new rule:
    // 1) if productImage is present and non-http, try that as asset name
    // 2) otherwise try model.number.png, model.number.jpg, and model.number (no ext)
    private var resolvedBundleImage: MEPlatformImage? {
        let prod = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1) If productImage is present and not a URL, try it as asset/bundle name
        if !prod.isEmpty && !prod.lowercased().starts(with: "http") {
            if let img = loadBundleImage(named: prod) { return img }
        }

        // 2) Try model.number-based filenames (user will rename to these)
        let trimmedNumber = model.number.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            "\(trimmedNumber).png",
            "\(trimmedNumber).jpg",
            "\(trimmedNumber).jpeg",
            trimmedNumber // try asset catalog name without extension
        ]

        for cand in candidates {
            if let img = loadBundleImage(named: cand) { return img }
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            // Image area
            ZStack(alignment: .topTrailing) {
                let imageHeight: CGFloat = imageMaxHeight

                if let url = resolvedRemoteURL {
                    // Remote URL
                    MERemoteImage(urlString: url)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: imageHeight)
                        .cornerRadius(6)
                        .padding(.top, 8)

                } else if let platformImage = resolvedBundleImage {
                    // Bundle image resolved (model number.png/.jpg or asset)
                    #if os(iOS)
                    Image(uiImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: imageHeight)
                        .cornerRadius(6)
                        .padding(.top, 8)
                    #else
                    Image(nsImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: imageHeight)
                        .cornerRadius(6)
                        .padding(.top, 8)
                    #endif

                } else {
                    // Placeholder
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: imageHeight * 0.9)
                        .opacity(0.35)
                        .cornerRadius(6)
                        .padding(.top, 8)
                }

                if model.built {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.blue)
                        .padding(6)
                        .accessibilityLabel("Unboxed")
                }

                // Removed wishlist toggle overlay from here (per instructions)
            }

            // Title area
            VStack(alignment: .leading, spacing: 4) {
                Text(model.productCode.isEmpty ? (model.firstReleaseYear.map { "First released \($0)" } ?? model.type) : model.productCode)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(model.statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)

            Spacer()

            // Bottom controls (modified per instructions)
            HStack {
                // 1) Favorite
                ZStack(alignment: .topTrailing) {
                    Button {
                        if purchaseManager.isUnlocked {
                            dataManager.toggleFavorite(for: model)
                        }
                    } label: {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundColor(model.isFavorite ? .yellow : .gray)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!purchaseManager.isUnlocked)

                    if !purchaseManager.isUnlocked {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.gray.opacity(0.8))
                            )
                            .offset(x: 6, y: -6)
                    }
                }

                Spacer()

                // 2) Wishlist
                ZStack(alignment: .topTrailing) {
                    Button {
                        if purchaseManager.isUnlocked {
                            dataManager.toggleWishlist(for: model)
                        }
                    } label: {
                        Image(systemName: model.isWishlisted ? "gift.fill" : "gift")
                            .font(.system(size: 16))
                            .foregroundColor(model.isWishlisted ? .pink : .gray)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!purchaseManager.isUnlocked)

                    if !purchaseManager.isUnlocked {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.gray.opacity(0.8))
                            )
                            .offset(x: 6, y: -6)
                    }
                }

                Spacer()

                // 3) Checkbox
                Button {
                    dataManager.toggleChecked(for: model)
                } label: {
                    Image(systemName: model.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundColor(model.checked ? accentColor : .gray)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                // 4) Link (placeholder when missing to preserve spacing)
                if !model.link.isEmpty {
                    Button {
                        openURL(model.link)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 8)
        }
        .frame(height: tileHeight)
        .background(model.checked ? accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}


// Replaces CategoryGridView — uses List to match List row styling exactly
struct CategoryGridView: View {
    let categorizedModels: [String: [MetalModel]]
    @Binding var expandedCategories: Set<String>
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?

    // layout tuning
    private let minColWidth: CGFloat = 140
    private let maxColumns: Int = 6
    private let minColumnsOnPhone: Int = 2
    private let tileSpacing: CGFloat = 12

    var body: some View {
        List {
            ForEach(categorizedModels.keys.sorted(), id: \.self) { category in
                let models = categorizedModels[category] ?? []
                let isComplete = !models.isEmpty && models.allSatisfy { $0.checked }

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { isExpanded in
                            withAnimation {
                                if isExpanded {
                                    expandedCategories.insert(category)
                                } else {
                                    expandedCategories.remove(category)
                                }
                            }
                        }
                    )
                ) {
                    // Wrap content in VStack and remove List insets
                    VStack(alignment: .leading, spacing: tileSpacing) {
                        if models.isEmpty {
                            Text("No cars")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            // Compute column count from screen width
                            let screenWidth = UIScreen.main.bounds.width
                            let horizontalInset: CGFloat = 32 // Approx List inset
                            let available = max(0, screenWidth - horizontalInset)
                            let columns = computeColumns(for: available)

                            LazyVGrid(columns: columns, spacing: tileSpacing) {
                                ForEach(models, id: \.id) { model in
                                    ModelGridItemView(
                                        model: model,
                                        accentColor: accentColor,
                                        dataManager: dataManager,
                                        onSelect: { selectedModel = model }
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 0, trailing: 16)) // keep some trailing padding
                } label: {
                    HStack {
                        Text(category)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        if isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                        }
                    }
                }
                .listRowBackground(isComplete ? accentColor.opacity(0.05) : Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private func computeColumns(for availableWidth: CGFloat) -> [GridItem] {
        let minWidth = max(availableWidth, minColWidth * CGFloat(minColumnsOnPhone))
        var count = max(1, Int(minWidth / minColWidth))
        if availableWidth < 500 { count = max(minColumnsOnPhone, count) }
        count = min(maxColumns, count)
        if count <= 1 { count = minColumnsOnPhone }
        return Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: count)
    }
}



// Plain grid: a single two-column grid for filteredModels
struct PlainGridView: View {
    let models: [MetalModel]
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?

    private let minColWidth: CGFloat = 140
    private let tileSpacing: CGFloat = 12
    private let horizontalInset: CGFloat = 16 // space on the sides

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minColWidth), spacing: tileSpacing)],
                spacing: tileSpacing
            ) {
                ForEach(models, id: \.id) { model in
                    ModelGridItemView(
                        model: model,
                        accentColor: accentColor,
                        dataManager: dataManager,
                        onSelect: { selectedModel = model }
                    )
                }
            }
            .padding(.vertical)
            .padding(.horizontal, horizontalInset)
        }
    }
}

// Add this extension for convenience
extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) {
            remove(element)
        } else {
            insert(element)
        }
    }
}

struct DeveloperBanner: View {
    var onOpenSettings: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14, weight: .bold))
            Text("Developer Mode Active")
                .font(.footnote.weight(.semibold))
            Spacer()
            Button(action: { onOpenSettings?() }) {
                Text("Settings")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.red.opacity(0.9), Color.orange.opacity(0.9)]), startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
        .padding(.top, 0)
    }
}

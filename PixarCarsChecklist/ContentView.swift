import SwiftUI
import SwiftData
import ImageIO
import SDWebImage
import SDWebImageSwiftUI

private let gridThumbnailPixelSize = CGSize(width: 220, height: 220)

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

private final class MEBundleImageCache {
    static let shared = MEBundleImageCache()

    private let cache = NSCache<NSString, MEPlatformImage>()
    private let lock = NSLock()
    private var missingNames: Set<String> = []

    private init() {
        cache.countLimit = 500
    }

    func image(named rawName: String, loader: () -> MEPlatformImage?) -> MEPlatformImage? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        lock.lock()
        let isKnownMissing = missingNames.contains(name)
        lock.unlock()
        guard !isKnownMissing else { return nil }

        guard let image = loader() else {
            lock.lock()
            missingNames.insert(name)
            lock.unlock()
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func cachedImage(named rawName: String) -> MEPlatformImage? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return cache.object(forKey: name as NSString)
    }
}

func bundleImageCandidates(for model: MetalModel) -> [String] {
    var candidates: [String] = []
    var seen: Set<String> = []

    func append(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
        candidates.append(trimmed)
    }

    let productImage = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
    if !productImage.isEmpty && !productImage.lowercased().starts(with: "http") {
        append(productImage)
    }

    let number = model.number.trimmingCharacters(in: .whitespacesAndNewlines)
    append("\(number).png")
    append("\(number).jpg")
    append("\(number).jpeg")
    append(number)

    return candidates
}

func remoteImageURLString(for model: MetalModel) -> String? {
    let productImage = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !productImage.isEmpty else { return nil }
    return productImage.lowercased().starts(with: "http") ? productImage : nil
}

private func resolveBundleImage(candidates: [String]) -> MEPlatformImage? {
    for candidate in candidates {
        if let image = loadBundleImage(named: candidate) {
            return image
        }
    }
    return nil
}

final class MEBundleImagePrefetcher {
    static let shared = MEBundleImagePrefetcher()

    private let queue = DispatchQueue(label: "com.mattjproductions.pixarcars.gridImagePrefetch", qos: .utility)
    private let lock = NSLock()
    private var generation = 0

    private init() {}

    func prefetch(candidatesList: [[String]], limit: Int = 120) {
        let work = Array(candidatesList.lazy.filter { !$0.isEmpty }.prefix(limit))
        guard !work.isEmpty else { return }

        lock.lock()
        generation += 1
        let currentGeneration = generation
        lock.unlock()

        queue.async { [weak self] in
            for candidates in work {
                guard self?.isCurrent(currentGeneration) == true else { return }
                _ = resolveBundleImage(candidates: candidates)
            }
        }
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }
}

private final class MERemoteImageFailureCache {
    static let shared = MERemoteImageFailureCache()

    private let lock = NSLock()
    private var failedURLStrings: Set<String> = []

    private init() {}

    func contains(_ urlString: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedURLStrings.contains(urlString)
    }

    func insert(_ urlString: String) {
        lock.lock()
        failedURLStrings.insert(urlString)
        lock.unlock()
    }
}

final class MERemoteImagePrefetcher {
    static let shared = MERemoteImagePrefetcher()

    private let lock = NSLock()
    private var token: SDWebImagePrefetchToken?
    private var lastSignature = ""

    private init() {
        MERemoteImageConfiguration.configure()
        SDWebImagePrefetcher.shared.maxConcurrentPrefetchCount = 2
    }

    func prefetch(urlStrings: [String], limit: Int = 24) {
        var seen: Set<String> = []
        let urls = urlStrings.compactMap { raw -> URL? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  seen.insert(value).inserted,
                  !MERemoteImageFailureCache.shared.contains(value)
            else { return nil }
            return URL(string: value)
        }.prefix(limit)

        let urlList = Array(urls)
        let signature = urlList.map(\.absoluteString).joined(separator: "|")

        lock.lock()
        guard signature != lastSignature else {
            lock.unlock()
            return
        }
        lastSignature = signature
        let oldToken = token
        lock.unlock()

        oldToken?.cancel()
        guard !urlList.isEmpty else { return }

        let context: [SDWebImageContextOption: Any] = [
            .imageThumbnailPixelSize: gridThumbnailPixelSize
        ]
        let newToken = SDWebImagePrefetcher.shared.prefetchURLs(
            urlList,
            options: [.lowPriority, .scaleDownLargeImages],
            context: context,
            progress: nil,
            completed: nil
        )

        lock.lock()
        token = newToken
        lock.unlock()
    }
}

private enum MERemoteImageConfiguration {
    private static let apply: Void = {
        SDWebImageDownloader.shared.config.downloadTimeout = 8
        SDWebImageDownloader.shared.config.maxConcurrentDownloads = 4
        SDImageCache.shared.config.maxMemoryCost = UInt(70 * 1024 * 1024)
        SDImageCache.shared.config.maxDiskSize = UInt(250 * 1024 * 1024)
    }()

    static func configure() {
        _ = apply
    }
}

final class MEBundleImageLoader: ObservableObject {
    @Published var image: MEPlatformImage?

    private let candidates: [String]
    private var isLoading = false

    init(candidates: [String]) {
        self.candidates = candidates
        self.image = candidates.lazy.compactMap { MEBundleImageCache.shared.cachedImage(named: $0) }.first
    }

    func load() {
        guard image == nil, !isLoading, !candidates.isEmpty else { return }
        isLoading = true

        let candidates = self.candidates
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let resolved = resolveBundleImage(candidates: candidates)
            DispatchQueue.main.async {
                self?.image = resolved
                self?.isLoading = false
            }
        }
    }
}

struct MELocalBundleImage: View {
    @StateObject private var loader: MEBundleImageLoader
    let imageHeight: CGFloat

    init(candidates: [String], imageHeight: CGFloat) {
        self.imageHeight = imageHeight
        _loader = StateObject(wrappedValue: MEBundleImageLoader(candidates: candidates))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                #endif
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.35)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: imageHeight)
        .cornerRadius(6)
        .padding(.top, 8)
        .onAppear { loader.load() }
    }
}

private final class MERemoteImageCache {
    static let shared = MERemoteImageCache()

    private let cache = NSCache<NSString, MEPlatformImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for urlString: String) -> MEPlatformImage? {
        cache.object(forKey: urlString as NSString)
    }

    func set(_ image: MEPlatformImage, for urlString: String, cost: Int) {
        cache.setObject(image, forKey: urlString as NSString, cost: cost)
    }
}

private func decodePlatformImage(from data: Data, maxPixelSize: Int = 700) -> MEPlatformImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        return nil
    }

    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        return nil
    }

    #if os(iOS)
    return UIImage(cgImage: cgImage)
    #else
    return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    #endif
}

/// Robust bundle loader: tries asset catalog name (no ext), then path(forResource:)
func loadBundleImage(named assetName: String) -> MEPlatformImage? {
    MEBundleImageCache.shared.image(named: assetName) {
        let ns = (assetName.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
        let resource = ns.deletingPathExtension
        let ext = ns.pathExtension.lowercased()

        #if os(iOS)
        if let img = UIImage(named: resource) { return img }
        #else
        if let img = NSImage(named: NSImage.Name(resource)) { return img }
        #endif

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
        if let cached = MERemoteImageCache.shared.image(for: urlString) {
            self.image = cached
            return
        }

        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data, let decoded = decodePlatformImage(from: data) else { return }
            MERemoteImageCache.shared.set(decoded, for: urlString, cost: data.count)
            DispatchQueue.main.async {
                self?.image = decoded
            }
        }
        task?.resume()
    }
}

struct MERemoteImage: View {
    private let urlString: String?
    private let url: URL?
    @State private var didFail = false

    init(urlString: String?) {
        MERemoteImageConfiguration.configure()
        self.urlString = urlString
        if let urlString {
            self.url = URL(string: urlString)
        } else {
            self.url = nil
        }
    }

    var body: some View {
        content
        .onChange(of: url) { _, _ in
            didFail = false
        }
    }

    private var content: AnyView {
        guard let url, !didFail else {
            return AnyView(fallbackImage)
        }
        if let urlString, MERemoteImageFailureCache.shared.contains(urlString) {
            return AnyView(fallbackImage)
        }

        let image = WebImage(
            url: url,
            options: [.lowPriority, .scaleDownLargeImages],
            context: [.imageThumbnailPixelSize: gridThumbnailPixelSize]
        ) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .onFailure { _ in
            if let urlString {
                MERemoteImageFailureCache.shared.insert(urlString)
            }
            didFail = true
        }

        return AnyView(image)
    }

    private var fallbackImage: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .opacity(0.35)
            .frame(maxWidth: .infinity, minHeight: 56)
    }
}

func sortMetalModels(_ models: [MetalModel], by sortOption: String, ascending: Bool = true) -> [MetalModel] {
    switch sortOption {
    case "name":
        return models.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    case "number":
        return models.sorted {
            let order = $0.number.localizedStandardCompare($1.number)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    case "firstReleaseYear":
        return models.sorted {
            let lhs = $0.firstReleaseYear ?? Int.max
            let rhs = $1.firstReleaseYear ?? Int.max
            if lhs != rhs {
                if $0.firstReleaseYear == nil { return false }
                if $1.firstReleaseYear == nil { return true }
                return ascending ? lhs < rhs : lhs > rhs
            }
            let order = $0.number.localizedStandardCompare($1.number)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    case "productCode":
        return models.sorted {
            let lhs = $0.productCode.isEmpty ? $0.number : $0.productCode
            let rhs = $1.productCode.isEmpty ? $1.number : $1.productCode
            let order = lhs.localizedStandardCompare(rhs)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    case "releaseDate":
        return models.sorted {
            switch ($0.releaseDateValue, $1.releaseDateValue) {
            case let (lhs?, rhs?) where lhs != rhs:
                return ascending ? lhs < rhs : lhs > rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let order = $0.number.localizedStandardCompare($1.number)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
    default:
        return models
    }
}

let specialModelStatuses: Set<String> = ["Coming Soon", "Exclusive", "Retired"]

struct VisibleModelSnapshot {
    let models: [MetalModel]
    let categorizedModels: [String: [MetalModel]]
    let sortedCategories: [String]
    let categorySet: Set<String>
    let completeCategories: Set<String>
    let collected: Int
    let total: Int
    let prefetchSignature: String
}

struct CatalogFilterPopover: View {
    @Binding var showCollected: Bool
    @Binding var showUncollected: Bool
    @Binding var showBuilt: Bool
    @Binding var showUnbuilt: Bool
    @Binding var showComingSoon: Bool
    @Binding var showExclusive: Bool
    @Binding var showRetired: Bool
    @Binding var showNormal: Bool
    @Binding var hiddenCategories: Set<String>

    let categories: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterGroup("Collection") {
                    Toggle("Collected", isOn: protectedBinding($showCollected, requiresOneOf: $showUncollected))
                        .disabled(showCollected && !showUncollected)
                    Toggle("Uncollected", isOn: protectedBinding($showUncollected, requiresOneOf: $showCollected))
                        .disabled(showUncollected && !showCollected)
                }

                filterGroup("Packaging") {
                    Toggle("Unboxed", isOn: protectedBinding($showBuilt, requiresOneOf: $showUnbuilt))
                        .disabled(showBuilt && !showUnbuilt)
                    Toggle("Carded / Not set", isOn: protectedBinding($showUnbuilt, requiresOneOf: $showBuilt))
                        .disabled(showUnbuilt && !showBuilt)
                }

                filterGroup("Status") {
                    Toggle("Normal", isOn: $showNormal)
                    Toggle("Coming Soon", isOn: $showComingSoon)
                    Toggle("Exclusive", isOn: $showExclusive)
                    Toggle("Retired", isOn: $showRetired)
                }

                if !categories.isEmpty {
                    filterGroup("Categories") {
                        ForEach(categories, id: \.self) { category in
                            Toggle(category, isOn: categoryBinding(category))
                        }
                        Button("Show All Categories") {
                            hiddenCategories.removeAll()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(16)
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        .frame(width: 300, height: min(520, 190 + CGFloat(categories.count) * 32))
        #endif
    }

    @ViewBuilder
    private func filterGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func protectedBinding(_ primary: Binding<Bool>, requiresOneOf other: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { primary.wrappedValue },
            set: { newValue in
                if !newValue && !other.wrappedValue {
                    return
                }
                primary.wrappedValue = newValue
            }
        )
    }

    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenCategories.contains(category) },
            set: { newValue in
                if newValue {
                    hiddenCategories.remove(category)
                } else {
                    hiddenCategories.insert(category)
                }
            }
        )
    }
}

struct CatalogSortControl: View {
    @Binding var sortOption: String
    @Binding var sortAscending: Bool

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Name") { sortOption = "name" }
                Button("Product Code") { sortOption = "productCode" }
                Button("First Release") { sortOption = "firstReleaseYear" }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .accessibilityLabel("Sort")
            #if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain)
            #endif

            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .accessibilityLabel(sortAscending ? "Ascending" : "Descending")
            #if os(macOS) || targetEnvironment(macCatalyst)
            .buttonStyle(.plain)
            #endif
        }
    }
}

func normalizedModelType(_ model: MetalModel) -> String {
    model.type.isEmpty ? "1:55 Die-Cast" : model.type
}

func modelMatchesType(_ model: MetalModel, selectedType: String) -> Bool {
    guard selectedType != "All" else { return true }
    return normalizedModelType(model) == selectedType
}

func modelMatchesSearch(_ model: MetalModel, query: String, includeExtendedFields: Bool) -> Bool {
    guard !query.isEmpty else { return true }

    if model.matches(query) {
        return true
    }

    guard includeExtendedFields else { return false }
    return model.status.lowercased().contains(query)
        || model.type.lowercased().contains(query)
        || model.releaseDate.lowercased().contains(query)
}

func makeTypeScopedCategories(
    from models: [MetalModel],
    selectedType: String
) -> [String] {
    var categories: Set<String> = []
    for model in models where modelMatchesType(
        model,
        selectedType: selectedType
    ) {
        categories.insert(model.category)
    }
    return categories.sorted()
}

func makeVisibleModelSnapshot(
    from sourceModels: [MetalModel],
    selectedType: String,
    searchText: String,
    hiddenCategories: Set<String>,
    showCollected: Bool,
    showUncollected: Bool,
    showBuilt: Bool,
    showUnbuilt: Bool,
    showComingSoon: Bool,
    showExclusive: Bool,
    showRetired: Bool,
    showNormal: Bool,
    sortOption: String,
    sortAscending: Bool,
    includeExtendedSearch: Bool
) -> VisibleModelSnapshot {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var filtered: [MetalModel] = []
    filtered.reserveCapacity(sourceModels.count)

    for model in sourceModels {
        guard modelMatchesType(
            model,
            selectedType: selectedType
        ) else { continue }

        guard hiddenCategories.isEmpty || !hiddenCategories.contains(model.category) else { continue }
        guard showCollected || !model.checked else { continue }
        guard showUncollected || model.checked else { continue }
        guard showBuilt || !model.built else { continue }
        guard showUnbuilt || model.built else { continue }

        let status = model.status
        let statusVisible =
            (showComingSoon && status == "Coming Soon")
            || (showExclusive && status == "Exclusive")
            || (showRetired && status == "Retired")
            || (showNormal && !specialModelStatuses.contains(status))
        guard statusVisible else { continue }

        guard modelMatchesSearch(model, query: query, includeExtendedFields: includeExtendedSearch) else { continue }
        filtered.append(model)
    }

    let sortedModels = sortMetalModels(filtered, by: sortOption, ascending: sortAscending)
    let categorizedModels = Dictionary(grouping: sortedModels, by: { $0.category })
    let sortedCategories = categorizedModels.keys.sorted()
    let completeCategories = Set(categorizedModels.compactMap { category, models in
        !models.isEmpty && models.allSatisfy { $0.checked } ? category : nil
    })
    let prefetchSignature = sortedModels
        .prefix(120)
        .map { "\($0.id.uuidString):\($0.productImage)" }
        .joined(separator: "|")

    return VisibleModelSnapshot(
        models: sortedModels,
        categorizedModels: categorizedModels,
        sortedCategories: sortedCategories,
        categorySet: Set(sortedCategories),
        completeCategories: completeCategories,
        collected: sortedModels.reduce(0) { $0 + ($1.checked ? 1 : 0) },
        total: sortedModels.count,
        prefetchSignature: prefetchSignature
    )
}



#if os(macOS)
import AppKit
#endif

struct ViewedCollectionState {
    let ownerID: String
    let ownerName: String
    let models: [MetalModel]
}

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
    @AppStorage("sortAscending") private var sortAscending = true
    @AppStorage("viewMode") private var viewMode = "categories"
    @AppStorage("selectedType") private var selectedType = "All"
    @State private var hiddenCategories: Set<String> = []
    @State private var selectedTab: Tab = .list
    @State private var selectedModel: MetalModel? = nil
    @State private var showingFilters = false
    @StateObject private var socialFeedStore = SocialFeedStore()
    @State private var viewedCollection: ViewedCollectionState?

    @AppStorage("showComingSoon") private var showComingSoon = true
    @AppStorage("showExclusive") private var showExclusive = true
    @AppStorage("showRetired") private var showRetired = true
    @AppStorage("showNormal") private var showNormal = true

    @AppStorage("showImageGrid") private var showImageGrid = false
    @AppStorage("catalogChromeCollapsed") private var catalogChromeCollapsed = false

    @AppStorage("devModeEnabled") private var devModeEnabled: Bool = false

    let accentColor = Color(hex: "D92D20")

    enum Tab {
        case list
        case gallery
        case favorites
        case wishlist
        case social
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
        makeTypeScopedCategories(
            from: activeModels,
            selectedType: selectedType
        )
    }

    private var activeModels: [MetalModel] {
        viewedCollection?.models ?? dataManager.allModels
    }

    private var isViewingCollection: Bool {
        viewedCollection != nil
    }

    private var filteredModels: [MetalModel] {
        filteredModels(using: debouncedSearchText)
    }

    private func filteredModels(using searchValue: String) -> [MetalModel] {
        var result = activeModels

        // Apply type filter
        if selectedType != "All" {
            result = result.filter { $0.type == selectedType }
        }

        // Apply search filter - change searchText to debouncedSearchText here
        // Optimize search filtering
        if !searchValue.isEmpty {
            let searchText = searchValue.lowercased()
            result = result.filter { model in
                model.name.lowercased().contains(searchText) ||
                model.searchableNumbers.contains(where: { $0.lowercased().contains(searchText) }) ||
                model.category.lowercased().contains(searchText)
            }
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

        return sortMetalModels(result, by: sortOption, ascending: sortAscending)
    }

    private var collectionStats: (collected: Int, total: Int) {
        collectionStats(for: filteredModels)
    }

    private func collectionStats(for models: [MetalModel]) -> (collected: Int, total: Int) {
        (models.filter { $0.checked }.count, models.count)
    }

    private func getCategorizedModels() -> [String: [MetalModel]] {
        categorizedModels(for: filteredModels)
    }

    private func categorizedModels(for models: [MetalModel]) -> [String: [MetalModel]] {
        Dictionary(grouping: models, by: { $0.category })
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
                    let visibleSnapshot = makeVisibleModelSnapshot(
                        from: activeModels,
                        selectedType: selectedType,
                        searchText: debouncedSearchText,
                        hiddenCategories: hiddenCategories,
                        showCollected: showCollected,
                        showUncollected: showUncollected,
                        showBuilt: showBuilt,
                        showUnbuilt: showUnbuilt,
                        showComingSoon: showComingSoon,
                        showExclusive: showExclusive,
                        showRetired: showRetired,
                        showNormal: showNormal,
                        sortOption: sortOption,
                        sortAscending: sortAscending,
                        includeExtendedSearch: false
                    )
                    let visibleModels = visibleSnapshot.models
                    let visibleCategorizedModels = visibleSnapshot.categorizedModels
                    let visibleCategorySet = visibleSnapshot.categorySet
                    let gridPrefetchKey = [
                        showImageGrid.description,
                        viewMode,
                        visibleSnapshot.prefetchSignature
                    ].joined(separator: "|")

                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            SearchBar(text: $searchText)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    catalogChromeCollapsed.toggle()
                                }
                            } label: {
                                Image(systemName: catalogChromeCollapsed ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 40, height: 36)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(catalogChromeCollapsed ? "Show catalogue controls" : "Hide catalogue controls")
                            .accessibilityHint("Shows or hides the logo, format filters, collection progress, and list controls")
                        }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .onChange(of: searchText) { oldValue, newValue in
                                searchDebouncer.run {
                                    debouncedSearchText = newValue
                                    // Automatically expand categories with matches when searching
                                    if !newValue.isEmpty {
                                        let matchingSnapshot = makeVisibleModelSnapshot(
                                            from: activeModels,
                                            selectedType: selectedType,
                                            searchText: newValue,
                                            hiddenCategories: hiddenCategories,
                                            showCollected: showCollected,
                                            showUncollected: showUncollected,
                                            showBuilt: showBuilt,
                                            showUnbuilt: showUnbuilt,
                                            showComingSoon: showComingSoon,
                                            showExclusive: showExclusive,
                                            showRetired: showRetired,
                                            showNormal: showNormal,
                                            sortOption: sortOption,
                                            sortAscending: sortAscending,
                                            includeExtendedSearch: false
                                        )
                                        expandedCategories.formUnion(matchingSnapshot.sortedCategories)
                                    }
                                }
                            }

                        if !catalogChromeCollapsed {
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

                            VStack(spacing: 10) {
                                CollectionStatsView(
                                    collected: visibleSnapshot.collected,
                                    total: visibleSnapshot.total,
                                    accentColor: accentColor
                                )
                                .padding(.top, 8)
                                HStack(spacing: 8) {
                                    Button {
                                        showingFilters.toggle()
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 16))
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                                        CatalogFilterPopover(
                                            showCollected: $showCollected,
                                            showUncollected: $showUncollected,
                                            showBuilt: $showBuilt,
                                            showUnbuilt: $showUnbuilt,
                                            showComingSoon: $showComingSoon,
                                            showExclusive: $showExclusive,
                                            showRetired: $showRetired,
                                            showNormal: $showNormal,
                                            hiddenCategories: $hiddenCategories,
                                            categories: typeScopedCategories
                                        )
                                    }

    #if os(macOS) || targetEnvironment(macCatalyst)
                                    .buttonStyle(.plain)
    #endif

                                    if viewMode == "categories" {
                                        Button(action: {
                                            let expandedVisibleCount = expandedCategories.intersection(visibleCategorySet).count

                                            withAnimation {
                                                if expandedVisibleCount == visibleCategorySet.count {
                                                    expandedCategories.subtract(visibleCategorySet)
                                                } else {
                                                    expandedCategories.formUnion(visibleCategorySet)
                                                }
                                            }
                                        }) {
                                            let allVisibleExpanded = !visibleCategorySet.isEmpty && expandedCategories.intersection(visibleCategorySet).count == visibleCategorySet.count

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

                                    CatalogSortControl(sortOption: $sortOption, sortAscending: $sortAscending)

                                    Button(action: {
                                        showImageGrid.toggle()
                                    }) {
                                        Image(systemName: showImageGrid ? "list.bullet" : "rectangle.grid.2x2")
                                            .font(.system(size: 16))
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .accessibilityLabel(showImageGrid ? "List view" : "Image grid")
    #if os(macOS) || targetEnvironment(macCatalyst)
                                    .buttonStyle(.plain)
    #endif

                                    Button(action: {
                                        viewMode = viewMode == "categories" ? "list" : "categories"
                                    }) {
                                        Image(systemName: viewMode == "categories" ? "list.bullet" : "rectangle.grid.1x2")
                                            .font(.system(size: 16))
                                            .padding(8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .accessibilityLabel(viewMode == "categories" ? "Unsorted list" : "Categorized list")
    #if os(macOS) || targetEnvironment(macCatalyst)
                                    .buttonStyle(.plain)
    #endif
                                }
                                .font(.caption)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }


                        if viewMode == "categories" {
                            if showImageGrid {
                                CategoryGridView(
                                    categorizedModels: visibleCategorizedModels,
                                    sortedCategories: visibleSnapshot.sortedCategories,
                                    completeCategories: visibleSnapshot.completeCategories,
                                    expandedCategories: $expandedCategories,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel,
                                    readOnly: isViewingCollection,
                                    onCollectionChanged: publishCollectionSnapshot
                                )
                                .padding(.bottom, bottomBarPadding)
                            } else {
                                CategoryListView(
                                    categorizedModels: visibleCategorizedModels,
                                    sortedCategories: visibleSnapshot.sortedCategories,
                                    completeCategories: visibleSnapshot.completeCategories,
                                    expandedCategories: $expandedCategories,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel,
                                    readOnly: isViewingCollection,
                                    onCollectionChanged: publishCollectionSnapshot
                                )
                                .padding(.bottom, bottomBarPadding)
                            }
                        } else {
                            if showImageGrid {
                                PlainGridView(
                                    models: visibleModels,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel,
                                    readOnly: isViewingCollection,
                                    onCollectionChanged: publishCollectionSnapshot
                                )
                                .padding(.bottom, bottomBarPadding)
                            } else {
                                PlainListView(
                                    models: visibleModels,
                                    accentColor: accentColor,
                                    dataManager: dataManager,
                                    selectedModel: $selectedModel,
                                    readOnly: isViewingCollection,
                                    onCollectionChanged: publishCollectionSnapshot
                                )
                                .padding(.bottom, bottomBarPadding)
                            }
                        }
                    }
                    .task(id: gridPrefetchKey) {
                        guard showImageGrid else { return }
                        let prefetchModels = Array(visibleModels.prefix(120))
                        MEBundleImagePrefetcher.shared.prefetch(
                            candidatesList: prefetchModels.map { bundleImageCandidates(for: $0) }
                        )
                        MERemoteImagePrefetcher.shared.prefetch(
                            urlStrings: prefetchModels.compactMap { remoteImageURLString(for: $0) }
                        )
                    }

                case .social:
                    SocialFeedView(
                        dataManager: dataManager,
                        store: socialFeedStore,
                        onViewCollection: viewCollection,
                        onPublishCollection: publishCollectionSnapshot
                    )
                        .padding(.bottom, bottomBarPadding)

                case .gallery:
                    if let viewedCollection {
                        ViewedCollectionPrivateGallery(ownerName: viewedCollection.ownerName)
                            .padding(.bottom, bottomBarPadding)
                    } else {
                        PhotoGalleryView(
                            dataManager: dataManager,
                            selectedTab: $selectedTab,
                            selectedModel: $selectedModel
                        )
                        .padding(.bottom, bottomBarPadding)
                    }

                case .favorites:
                    FavoritesView(
                        selectedTab: $selectedTab,
                        selectedModel: $selectedModel,
                        sourceModels: viewedCollection?.models.filter { $0.isFavorite },
                        readOnly: isViewingCollection,
                        onCollectionChanged: publishCollectionSnapshot
                    )
                    .environmentObject(dataManager)
                    .padding(.bottom, bottomBarPadding)

                case .wishlist:
                    WishlistView(
                        selectedTab: $selectedTab,
                        selectedModel: $selectedModel,
                        sourceModels: viewedCollection?.models.filter { $0.isWishlisted },
                        readOnly: isViewingCollection,
                        onCollectionChanged: publishCollectionSnapshot
                    )
                    .environmentObject(dataManager)
                    .padding(.bottom, bottomBarPadding)

                case .settings:
                    SettingsView(
                        socialFeedStore: socialFeedStore,
                        viewedCollection: viewedCollection,
                        onCloseViewedCollection: closeViewedCollection
                    )
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
    ModelDetailView(
        model: model,
        dataManager: dataManager,
        isReadOnly: isViewingCollection,
        onCollectionChanged: publishCollectionSnapshot
    )
        .environmentObject(socialFeedStore)
}

.toolbar {
    #if os(iOS) || targetEnvironment(macCatalyst)
    if selectedTab != .list || !catalogChromeCollapsed {
        ToolbarItem(placement: .principal) {
            Image("CarsChecklistLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("Pixar Cars Checklist")
        }
    }
    #else
    if selectedTab != .list || !catalogChromeCollapsed {
        ToolbarItem(placement: .automatic) {
            Image("CarsChecklistLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("Pixar Cars Checklist")
        }
    }
    #endif
}
#if os(iOS) || targetEnvironment(macCatalyst)
.toolbar(selectedTab == .list && catalogChromeCollapsed ? .hidden : .visible, for: .navigationBar)
#endif

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

	                    // Feed Button
	                    Button(action: {
	                        selectedTab = .social
	                        selectedModel = nil
	                    }) {
	                        VStack {
	                            Image(systemName: "bubble.left.and.bubble.right")
	                                .resizable()
	                                .scaledToFit()
	                                .frame(width: 24, height: 24)
	                            Text("Feed")
	                                .font(.caption)
	                        }
	                        .foregroundColor(selectedTab == .social ? accentColor : .gray)
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
            VStack(spacing: 0) {
                if devModeEnabled {
                    DeveloperBanner(onOpenSettings: { selectedTab = .settings })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let viewedCollection {
                    ViewingCollectionBanner(ownerName: viewedCollection.ownerName, onClose: closeViewedCollection)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .zIndex(2)
        }
    }

    private func publishCollectionSnapshot() {
        guard !isViewingCollection else { return }
        let models = dataManager.allModels
        Task {
            await socialFeedStore.publishCollectionSnapshot(models: models)
        }
    }

    private func viewCollection(_ user: SocialCommunityUser) {
        guard !user.isSelf else {
            closeViewedCollection()
            return
        }
        publishCollectionSnapshot()
        Task {
            guard let collection = await socialFeedStore.loadUserCollection(user) else { return }
            let state = makeViewedCollectionState(from: collection)
            await MainActor.run {
                viewedCollection = state
                selectedModel = nil
                selectedTab = .list
            }
        }
    }

    private func closeViewedCollection() {
        viewedCollection = nil
        selectedModel = nil
    }

    private func makeViewedCollectionState(from collection: SocialUserCollection) -> ViewedCollectionState {
        var backupsByIdentifier: [String: SocialCollectionModelBackup] = [:]
        for backup in collection.models {
            let key = backup.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                backupsByIdentifier[key] = backup
            }
        }

        let models = dataManager.allModels.map { model -> MetalModel in
            let backup = backupsByIdentifier[model.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)]
                ?? backupsByIdentifier[model.number.trimmingCharacters(in: .whitespacesAndNewlines)]

            return MetalModel(
                id: model.id,
                backupIdentifier: model.backupIdentifier,
                checked: backup?.checked ?? false,
                name: model.name,
                number: model.number,
                productCode: model.productCode,
                character: model.character,
                category: model.category,
                firstReleaseYear: model.firstReleaseYear,
                releaseCount: model.releaseCount,
                series: model.series,
                difficulty: model.difficulty,
                sheets: model.sheets,
                link: model.link,
                instructionsLink: model.instructionsLink,
                type: model.type,
                status: model.status,
                threeSixtyView: model.threeSixtyView,
                modelDescription: model.modelDescription,
                productImage: model.productImage,
                releaseDate: model.releaseDate,
                isFavorite: backup?.isFavorite ?? false,
                isWishlisted: backup?.isWishlisted ?? false,
                quantity: min(max(backup?.quantity ?? 0, 0), 100),
                built: backup?.built ?? false
            )
        }

        return ViewedCollectionState(
            ownerID: collection.owner.id,
            ownerName: collection.owner.displayName,
            models: models
        )
    }
}


struct CategoryListView: View {
    let categorizedModels: [String: [MetalModel]]
    let sortedCategories: [String]
    let completeCategories: Set<String>
    @Binding var expandedCategories: Set<String>
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    private func isCategoryComplete(_ category: String) -> Bool {
        completeCategories.contains(category)
    }

    var body: some View {
        List {
            ForEach(sortedCategories, id: \.self) { category in
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
                                dataManager: dataManager,
                                readOnly: readOnly,
                                onCollectionChanged: onCollectionChanged
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
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    var body: some View {
        List(models, id: \.id) { model in
            Button {
                selectedModel = model
            } label: {
                ModelRowView(
                    model: model,
                    accentColor: accentColor,
                    compact: false,
                    dataManager: dataManager,
                    readOnly: readOnly,
                    onCollectionChanged: onCollectionChanged
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
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}
    @EnvironmentObject var purchaseManager: PurchaseManager

    var body: some View {
        HStack(spacing: 0) {
            // Left Group - First 3 icons flush left
            HStack(spacing: compact ? 4 : 8) {
                // 1. Favorite Star
                ZStack(alignment: .bottomTrailing) {
                    Button {
                        guard !readOnly else { return }
                        if purchaseManager.isUnlocked {
                            dataManager.toggleFavorite(for: model)
                            onCollectionChanged()
                        }
                    } label: {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .font(.system(size: compact ? 18 : 20))
                            .foregroundColor(model.isFavorite ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)

                    if !readOnly && !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }

                // 1b. Wishlist (gift)
                ZStack(alignment: .bottomTrailing) {
                    Button {
                        guard !readOnly else { return }
                        if purchaseManager.isUnlocked {
                            dataManager.toggleWishlist(for: model)
                            onCollectionChanged()
                        }
                    } label: {
                        Image(systemName: model.isWishlisted ? "gift.fill" : "gift")
                            .font(.system(size: compact ? 18 : 20))
                            .foregroundColor(model.isWishlisted ? .pink : .gray)
                    }
                    .buttonStyle(.plain)

                    if !readOnly && !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }


                // 2. Quantity
                ZStack(alignment: .bottomTrailing) {
                    Menu {
                        if !readOnly && purchaseManager.isUnlocked {
                            ForEach(0..<11, id: \.self) { quantity in
                                Button {
                                    dataManager.updateQuantity(for: model, quantity: quantity)
                                    onCollectionChanged()
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

                    if !readOnly && !purchaseManager.isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray.opacity(0.7))
                            .offset(x: 2, y: 2)
                    }
                }


                // 3. Checkbox
                if alwaysShowCheckbox {
                    Button {
                        guard !readOnly else { return }
                        dataManager.toggleChecked(for: model)
                        onCollectionChanged()
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
                    .lineLimit(compact ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
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
            if !readOnly {
                Button {
                    dataManager.toggleChecked(for: model)
                    onCollectionChanged()
                } label: {
                    Label(model.checked ? "Mark Unchecked" : "Mark Checked",
                         systemImage: model.checked ? "square" : "checkmark.square.fill")
                }
                .tint(model.checked ? .gray : accentColor)
            }
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
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}
    @EnvironmentObject var purchaseManager: PurchaseManager
    var onSelect: (() -> Void)? = nil

    // Config
    private let tileHeight: CGFloat = 170
    private let imageMaxHeight: CGFloat = 56
    private let horizontalPadding: CGFloat = 10

    private var resolvedRemoteURL: String? {
        remoteImageURLString(for: model)
    }

    private var resolvedBundleImageCandidates: [String] {
        bundleImageCandidates(for: model)
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

                } else {
                    MELocalBundleImage(
                        candidates: resolvedBundleImageCandidates,
                        imageHeight: imageHeight
                    )
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
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
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
                        guard !readOnly else { return }
                        if purchaseManager.isUnlocked {
                            dataManager.toggleFavorite(for: model)
                            onCollectionChanged()
                        }
                    } label: {
                        Image(systemName: model.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundColor(model.isFavorite ? .yellow : .gray)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!readOnly && !purchaseManager.isUnlocked)

                    if !readOnly && !purchaseManager.isUnlocked {
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
                        guard !readOnly else { return }
                        if purchaseManager.isUnlocked {
                            dataManager.toggleWishlist(for: model)
                            onCollectionChanged()
                        }
                    } label: {
                        Image(systemName: model.isWishlisted ? "gift.fill" : "gift")
                            .font(.system(size: 16))
                            .foregroundColor(model.isWishlisted ? .pink : .gray)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!readOnly && !purchaseManager.isUnlocked)

                    if !readOnly && !purchaseManager.isUnlocked {
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
                    guard !readOnly else { return }
                    dataManager.toggleChecked(for: model)
                    onCollectionChanged()
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
    let sortedCategories: [String]
    let completeCategories: Set<String>
    @Binding var expandedCategories: Set<String>
    let accentColor: Color
    @ObservedObject var dataManager: DataManager
    @Binding var selectedModel: MetalModel?
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    // layout tuning
    private let minColWidth: CGFloat = 140
    private let maxColumns: Int = 6
    private let minColumnsOnPhone: Int = 2
    private let tileSpacing: CGFloat = 12

    var body: some View {
        List {
            ForEach(sortedCategories, id: \.self) { category in
                let models = categorizedModels[category] ?? []
                let isComplete = completeCategories.contains(category)

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
                                        readOnly: readOnly,
                                        onCollectionChanged: onCollectionChanged,
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
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

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
                        readOnly: readOnly,
                        onCollectionChanged: onCollectionChanged,
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

struct ViewingCollectionBanner: View {
    let ownerName: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .bold))
            Text("Showing \(ownerName) collection")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close viewed collection")
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "66D12D"))
    }
}

struct ViewedCollectionPrivateGallery: View {
    let ownerName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Photos are private")
                .font(.headline)
            Text("\(ownerName)'s collection status is visible here, but personal photos and notes stay private.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }

    private var background: Color {
        #if os(iOS) || targetEnvironment(macCatalyst)
        return Color(.systemGroupedBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
}

import SwiftData

#if canImport(UIKit)
import UIKit
private func compressImageData(_ data: Data,
                               maxDimension: CGFloat = 1600,
                               targetBytes: Int = 800_000) -> Data? {
    guard let img = UIImage(data: data) else { return nil }
    let long = max(img.size.width, img.size.height)
    let scale = min(1, maxDimension / max(1, long))
    let size  = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let rend  = UIGraphicsImageRenderer(size: size)
    let scaled = rend.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    for q in stride(from: 0.8, through: 0.4, by: -0.1) {
        if let d = scaled.jpegData(compressionQuality: q), d.count <= targetBytes { return d }
    }
    return scaled.jpegData(compressionQuality: 0.35)
}
#elseif canImport(AppKit)
import AppKit
private func compressImageData(_ data: Data,
                               maxDimension: CGFloat = 1600,
                               targetBytes: Int = 800_000) -> Data? {
    guard let img = NSImage(data: data),
          let rep = NSBitmapImageRep(data: img.tiffRepresentation ?? data) else { return nil }
    let long = max(CGFloat(rep.pixelsWide), CGFloat(rep.pixelsHigh))
    let scale = min(1, maxDimension / max(1, long))
    let size  = NSSize(width: CGFloat(rep.pixelsWide) * scale, height: CGFloat(rep.pixelsHigh) * scale)

    let canvas = NSImage(size: size)
    canvas.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(origin: .zero, size: size))
    canvas.unlockFocus()

    for q in stride(from: 0.8, through: 0.4, by: -0.1) {
        if let t = canvas.tiffRepresentation,
           let jpg = NSBitmapImageRep(data: t)?.representation(using: .jpeg, properties: [.compressionFactor: q]),
           jpg.count <= targetBytes { return jpg }
    }
    if let t = canvas.tiffRepresentation {
        return NSBitmapImageRep(data: t)?.representation(using: .jpeg, properties: [.compressionFactor: 0.35])
    }
    return nil
}
#endif


@MainActor
final class DataManager: ObservableObject {

    private static let appSchema = Schema([
        MetalModel.self,
        User.self,
        ModelPhoto.self,
        ModelNote.self,
        AppMeta.self
    ])

    static let shared = DataManager()

    private(set) var modelContainer: ModelContainer
    private(set) var modelContext: ModelContext

    @Published private(set) var allModels: [MetalModel] = []
    @Published private(set) var currentUser: User
    @Published private(set) var allPhotos: [ModelPhoto] = []
    @Published private(set) var allNotes: [ModelNote] = []
    @Published private(set) var isReady = false

    private static func appSupportFolder() -> URL {
        let root = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "PixarCarsChecklist"
        let folder = root.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func localStoreURL() -> URL {
        appSupportFolder().appendingPathComponent("default-v2.store", isDirectory: false)
    }

    private static func removeStore(at url: URL) {
        let fm  = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent // e.g. "default-v2.store"

        let candidates: [URL] = [
            url, // main sqlite
            dir.appendingPathComponent("\(base)-wal"),
            dir.appendingPathComponent("\(base)-shm"),
            dir.appendingPathComponent("\(base)_ExternalBinaryData"),
            dir.appendingPathComponent("\(base)_ExternalRecords")
        ]

        for u in candidates where fm.fileExists(atPath: u.path) {
            try? fm.removeItem(at: u)
        }
    }



//    to here

    /// Also remove any **legacy** SwiftData default store that might have been created
    /// before we started pinning a custom URL.
    private static func removeLegacyDefaultStoreIfPresent() {
        let legacy = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
            .appendingPathComponent("default.store", isDirectory: false)
        if let legacy { removeStore(at: legacy) }
    }

    // Lightweight caches (for category view performance)
    private let cacheQueue = DispatchQueue(label: "com.mattjproductions.pixarcars.cache", qos: .userInitiated)
    private var cachedCategorizedModels: [String: [MetalModel]] = [:]
    private var lastModelUpdateCount = 0
    private var lastSearchText = ""

    // Bump if you want a one-time “catalog import” gate. We also upsert every launch so new JSON rows are always added.
    private let bundledCatalogVersion = 1
    private let lastUpdatedKey = "catalogLastUpdated"

    private let developerSnapshotKey = "developerSnapshotV1"

    private struct SnapshotModelFlags: Codable {
        let number: String
        let checked: Bool
        let built: Bool
        let isFavorite: Bool
        let isWishlisted: Bool
        let quantity: Int
    }
    private struct SnapshotNote: Codable {
        let number: String
        let text: String
        let timestamp: Date
    }
    private struct SnapshotPhoto: Codable {
        let number: String
        let imageData: Data
        let timestamp: Date
    }
    private struct DeveloperSnapshot: Codable {
        let createdAt: Date
        let flags: [SnapshotModelFlags]
        let notes: [SnapshotNote]
        let photos: [SnapshotPhoto]
    }

    private enum ImportMode {
        case upsert
        case replaceFromDeveloperJSON
    }

    // MARK: - Init

    private init() {
        let storeURL = Self.localStoreURL()
        // 👇 Use the URL so SwiftData creates/opens *this* file
        let localConfig = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        let container: ModelContainer
        do {
            // Optional: clean up any truly old default store first
            Self.removeLegacyDefaultStoreIfPresent()

            container = try ModelContainer(for: Self.appSchema, configurations: [localConfig])
        } catch {
            // Hard reset if anything goes wrong opening
            Self.removeStore(at: storeURL)
            do {
                container = try ModelContainer(for: Self.appSchema, configurations: [localConfig])
            } catch {
                fatalError("Failed to open local store even after reset: \(error)")
            }
        }

        self.modelContainer = container
        self.modelContext = container.mainContext

        if let u = try? modelContext.fetch(FetchDescriptor<User>()).first {
            self.currentUser = u
        } else {
            let u = User()
            modelContext.insert(u)
            try? modelContext.save()
            self.currentUser = u
        }

        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in _ = await self?.refreshCatalogNow() }
        }
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in _ = await self?.refreshCatalogNow() }
        }
        #endif

        Task { @MainActor in
            self.enforceStableIDs(in: self.modelContext)
            self.refreshData()
            await self.initializePersistentStorage()
            self.isReady = true
        }
    }


    // MARK: - First run & every-run seeding

    private func initializePersistentStorage() async {
        print("[Catalog] initializePersistentStorage: starting")
        // Seed from JSON if empty
        if (try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) == 0 {
            print("[Catalog] Store empty: seeding from JSON…")
            await loadFromJSON(into: modelContext, owner: currentUser)
            print("[Catalog] Seed complete. Current model count: \((try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
        }
        print("[Catalog] Upserting bundled/remote JSON to add any new rows…")
        await loadFromJSON(into: modelContext, owner: currentUser)
        print("[Catalog] Upsert pass complete. Model count now: \((try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")

        print("[Catalog] Version gate check…")
        await runCatalogImportIfNeeded(in: modelContext, owner: currentUser)

        await loadFromJSON(into: modelContext, owner: currentUser)

        print("[Catalog] Enforcing stable IDs and de-duplicating…")
        enforceStableIDs(in: modelContext)

        try? modelContext.save()
        print("[Catalog] Saved context after init pipeline. Total models: \(allModels.count)")
        refreshData()
    }

    // Input model used only for decoding checked.json
    private struct JSONModel: Decodable {
        let checked: Bool
        let name: String
        let number: String
        let productCode: String
        let character: String
        let category: String
        let firstReleaseYear: Int?
        let releaseCount: Int
        let series: String
        let difficulty: Int?
        let sheets: Double
        let link: String
        let instructionsLink: String
        let type: String
        let status: String
        let threeSixtyView: String
        let modelDescription: String
        let productImage: String
        let built: Bool

        enum CodingKeys: String, CodingKey {
            case checked, name, number, productCode, character, category, firstReleaseYear, releaseCount, series
            case difficulty, sheets, link, instructionsLink, type, status, built
            case threeSixtyView = "360View"
            case modelDescription = "description"
            case productImage = "productimage"
            // "action" / "originalNumber" may exist but are ignored
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            checked = (try? c.decode(Bool.self, forKey: .checked)) ?? false
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            number = (try? c.decode(String.self, forKey: .number)) ?? ""
            productCode = (try? c.decode(String.self, forKey: .productCode)) ?? ""
            character = (try? c.decode(String.self, forKey: .character)) ?? ""
            category = (try? c.decode(String.self, forKey: .category)) ?? "Uncategorized"
            firstReleaseYear = try? c.decode(Int.self, forKey: .firstReleaseYear)
            releaseCount = (try? c.decode(Int.self, forKey: .releaseCount)) ?? 0
            series = (try? c.decode(String.self, forKey: .series)) ?? ""
            difficulty = try? c.decode(Int.self, forKey: .difficulty)
            sheets = (try? c.decode(Double.self, forKey: .sheets)) ?? 0
            link = (try? c.decode(String.self, forKey: .link)) ?? ""
            instructionsLink = (try? c.decode(String.self, forKey: .instructionsLink)) ?? ""
            type = (try? c.decode(String.self, forKey: .type)) ?? ""
            status = (try? c.decode(String.self, forKey: .status)) ?? ""
            built = (try? c.decode(Bool.self, forKey: .built)) ?? false
            threeSixtyView = (try? c.decode(String.self, forKey: .threeSixtyView)) ?? ""
            modelDescription = (try? c.decode(String.self, forKey: .modelDescription)) ?? ""
            productImage = (try? c.decode(String.self, forKey: .productImage)) ?? ""
        }
    }



    // Upsert-from-JSON: never overwrites user flags (checked/built/favorite/quantity/owner)
    private func loadFromJSON(into context: ModelContext, owner: User, mode: ImportMode = .upsert) async {
        print("[Catalog] loadFromJSON: start")
        let preCount = (try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1
        print("[Catalog] Existing models before import: \(preCount)")
        // Determine remote catalog URL: respect Developer Mode override if enabled
        let defaultCatalogURLString = "https://pixar-cars-catalog.mattjones7416.workers.dev/api/catalog"
        let devModeEnabled = UserDefaults.standard.bool(forKey: "devModeEnabled")
        let devURLString = (UserDefaults.standard.string(forKey: "devCatalogURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCatalogURLString: String = {
            if devModeEnabled, let url = URL(string: devURLString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return devURLString
            }
            return defaultCatalogURLString
        }()

        func fetchRemoteData() async throws -> Data {
            print("[Catalog] Attempting remote fetch (cache-busted): \(remoteCatalogURLString)")
            guard var components = URLComponents(string: remoteCatalogURLString) else {
                throw URLError(.badURL)
            }
            // Add cache-busting query parameter so CDN/proxies don’t serve stale JSON
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
            components.queryItems = queryItems
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            #if os(iOS)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            #endif
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse { print("[Catalog] Remote HTTP status: \(http.statusCode)") }
            print("[Catalog] Remote bytes received: \(data.count)")
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }

        func loadBundledData() throws -> Data {
            guard let url = Bundle.main.url(forResource: "checked", withExtension: "json") else {
                throw NSError(domain: "DataManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "checked.json not found in bundle"])
            }
            return try Data(contentsOf: url)
        }

        do {
            // Try remote first
            print("[Catalog] Remote fetch succeeded. Beginning upsert…")
            let data = try await fetchRemoteData()
            switch mode {
            case .upsert:
                try await upsert(from: data, into: context, owner: owner)
            case .replaceFromDeveloperJSON:
                try await replaceCatalog(from: data, into: context, owner: owner)
            }
            print("✅ [Catalog] Loaded from remote and upserted. Pre-count: \(preCount), Post-count: \((try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
            return
        } catch {
            print("⚠️ [Catalog] Remote fetch failed: \(error) — falling back to bundle")
        }

        do {
            // Fallback to bundled file
            let data = try loadBundledData()
            print("[Catalog] Loaded bundled JSON (bytes: \(data.count)). Beginning upsert…")
            switch mode {
            case .upsert:
                try await upsert(from: data, into: context, owner: owner)
            case .replaceFromDeveloperJSON:
                try await replaceCatalog(from: data, into: context, owner: owner)
            }
            print("✅ [Catalog] Loaded from bundle and upserted. Pre-count: \(preCount), Post-count: \((try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
        } catch {
            print("❌ [Catalog] JSON import failed: \(error)")
        }
    }

    // Helper to keep the original upsert logic intact
    private func upsert(from data: Data, into context: ModelContext, owner: User) async throws {
        let decoder = JSONDecoder()
        print("[Catalog] Upsert: decoding JSON (bytes: \(data.count))…")
        let items = try decoder.decode([JSONModel].self, from: data)
        print("[Catalog] Upsert: decoded items: \(items.count)")

        // Existing models keyed by number
        let existing = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        var byNumber = Dictionary(uniqueKeysWithValues: existing.map { ($0.number, $0) })

        let existingCount = existing.count
        var updated = 0
        var inserted = 0

        for jm in items {
            if let m = byNumber[jm.number] {
                updated += 1
                // Update only catalog metadata
                m.name = jm.name
                m.productCode = jm.productCode
                m.character = jm.character
                m.category = jm.category
                m.firstReleaseYear = jm.firstReleaseYear
                m.releaseCount = jm.releaseCount
                m.series = jm.series
                m.difficulty = jm.difficulty
                m.sheets = jm.sheets
                m.link = jm.link
                m.instructionsLink = jm.instructionsLink
                m.type = jm.type
                m.status = jm.status
                m.threeSixtyView = jm.threeSixtyView
                m.modelDescription = jm.modelDescription
                m.productImage = jm.productImage
            } else {
                inserted += 1
                // Insert new row
                let model = MetalModel(
                    id: MetalModel.stableID(for: jm.number),
                    backupIdentifier: jm.number,
                    checked: jm.checked,
                    name: jm.name,
                    number: jm.number,
                    productCode: jm.productCode,
                    character: jm.character,
                    category: jm.category,
                    firstReleaseYear: jm.firstReleaseYear,
                    releaseCount: jm.releaseCount,
                    series: jm.series,
                    difficulty: jm.difficulty,
                    sheets: jm.sheets,
                    link: jm.link,
                    instructionsLink: jm.instructionsLink,
                    type: jm.type,
                    status: jm.status,
                    threeSixtyView: jm.threeSixtyView,
                    modelDescription: jm.modelDescription,
                    productImage: jm.productImage,
                    isFavorite: false,
                    isWishlisted: false,
                    quantity: jm.checked ? 1 : 0,
                    built: jm.built
                )
                model.owner = owner
                context.insert(model)
                byNumber[jm.number] = model
            }
        }
        print("[Catalog] Upsert: existing=\(existingCount), updated=\(updated), inserted=\(inserted)")
        try context.save()
        let postCount = (try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1
        print("[Catalog] Upsert: save complete. Total models now: \(postCount)")
    }

    // Replace-mode import used by Developer Mode: keeps only models present in the JSON,
    // but preserves user flags when numbers/backupIdentifiers match.
    private func replaceCatalog(from data: Data, into context: ModelContext, owner: User) async throws {
        let decoder = JSONDecoder()
        let items = try decoder.decode([JSONModel].self, from: data)

        // Build lookup of desired numbers from JSON
        let desiredByNumber = Dictionary(uniqueKeysWithValues: items.map { ($0.number, $0) })

        // Fetch existing models
        let existingModels = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        let existingByNumber = Dictionary(uniqueKeysWithValues: existingModels.map { ($0.number, $0) })

        // 1) Delete any existing models whose number is NOT in the dev JSON
        for model in existingModels where desiredByNumber[model.number] == nil {
            context.delete(model)
        }

        // 2) Upsert for items in JSON, preserving user flags on matches
        for jm in items {
            if let existing = existingByNumber[jm.number] {
                // Update catalog fields, preserve user flags
                existing.name = jm.name
                existing.productCode = jm.productCode
                existing.character = jm.character
                existing.category = jm.category
                existing.firstReleaseYear = jm.firstReleaseYear
                existing.releaseCount = jm.releaseCount
                existing.series = jm.series
                existing.difficulty = jm.difficulty
                existing.sheets = jm.sheets
                existing.link = jm.link
                existing.instructionsLink = jm.instructionsLink
                existing.type = jm.type
                existing.status = jm.status
                existing.threeSixtyView = jm.threeSixtyView
                existing.modelDescription = jm.modelDescription
                existing.productImage = jm.productImage
            } else {
                // Insert new row with user flags defaulted based on JSON
                let model = MetalModel(
                    id: MetalModel.stableID(for: jm.number),
                    backupIdentifier: jm.number,
                    checked: jm.checked,
                    name: jm.name,
                    number: jm.number,
                    productCode: jm.productCode,
                    character: jm.character,
                    category: jm.category,
                    firstReleaseYear: jm.firstReleaseYear,
                    releaseCount: jm.releaseCount,
                    series: jm.series,
                    difficulty: jm.difficulty,
                    sheets: jm.sheets,
                    link: jm.link,
                    instructionsLink: jm.instructionsLink,
                    type: jm.type,
                    status: jm.status,
                    threeSixtyView: jm.threeSixtyView,
                    modelDescription: jm.modelDescription,
                    productImage: jm.productImage,
                    isFavorite: false,
                    isWishlisted: false,
                    quantity: jm.checked ? 1 : 0,
                    built: jm.built
                )
                model.owner = owner
                context.insert(model)
            }
        }

        // Save and refresh caches
        try context.save()
    }

    // Optional one-shot version gate (kept for future use)
    private func runCatalogImportIfNeeded(in context: ModelContext, owner: User) async {
        print("[Catalog] runCatalogImportIfNeeded: bundled=\(bundledCatalogVersion)")
        let fd = FetchDescriptor<AppMeta>(predicate: #Predicate { $0.key == "catalogVersion" })
        let current = try? context.fetch(fd).first
        let currentVersion = current?.intValue ?? 0
        print("[Catalog] Current catalogVersion in store: \(currentVersion)")
        guard bundledCatalogVersion > currentVersion else { print("[Catalog] Version gate: up-to-date; skipping import"); return }

        print("[Catalog] Version gate: importing new catalog version…")
        await loadFromJSON(into: context, owner: owner)

        let meta = current ?? AppMeta(key: "catalogVersion", intValue: 0)
        meta.intValue = bundledCatalogVersion
        if current == nil { context.insert(meta) }
        try? context.save()
        print("[Catalog] Version gate: saved new version=\(bundledCatalogVersion)")
    }


    // MARK: - User actions

    @MainActor
    func toggleFavorite(for model: MetalModel) {
        if let m = try? fetchByID(model.id) { m.isFavorite.toggle(); saveContext() }
    }

    @MainActor
    func toggleChecked(for model: MetalModel) {
        if let m = try? fetchByID(model.id) {
            m.checked.toggle()
            m.quantity = m.checked ? max(1, m.quantity) : 0
            saveContext()
        }
    }

    @MainActor
    func toggleBuilt(for model: MetalModel) {
        if let m = try? fetchByID(model.id) { m.built.toggle(); saveContext() }
    }

    @MainActor
    func updateQuantity(for model: MetalModel, quantity: Int) {
        guard let m = try? fetchByID(model.id) else { return }
        m.quantity = quantity
        m.checked = quantity > 0
        saveContext()
    }

    // MARK: - Wishlist

    @MainActor
    func toggleWishlist(for model: MetalModel) {
        if let m = try? fetchByID(model.id) {
            m.isWishlisted.toggle()
            saveContext()
        }
    }

    func getWishlistedModels(searchText: String = "") -> [MetalModel] {
        let base = allModels.filter { $0.isWishlisted }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.matches(searchText) }
    }

    /// Export a shareable plain-text list of wishlisted models including number, name, and link
    func generateWishlistShareText() -> String {
        let items = allModels
            .filter { $0.isWishlisted }
            .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        guard !items.isEmpty else { return "" }
        let lines = items.map { m in
            let link = m.link.isEmpty ? m.instructionsLink : m.link
            let code = m.productCode.isEmpty ? m.number : m.productCode
            return "\(code) — \(m.name) — \(link)"
        }
        return lines.joined(separator: "\n")
    }



    // ADDED THESE

    // Add near other public helpers
    @MainActor
    func handleJSONUpdates() async {
        await loadFromJSON(into: modelContext, owner: currentUser)   // additive import
        enforceStableIDs(in: modelContext)
        try? modelContext.save()
        refreshData()
    }

    @MainActor
    func resetAndReloadData() async -> Bool {
        // wipe catalog + user content, then re-import from JSON
        do {
            // delete photos + notes
            for p in (try modelContext.fetch(FetchDescriptor<ModelPhoto>())) { modelContext.delete(p) }
            for n in (try modelContext.fetch(FetchDescriptor<ModelNote>()))  { modelContext.delete(n) }
            // delete models
            for m in (try modelContext.fetch(FetchDescriptor<MetalModel>())) { modelContext.delete(m) }
            try modelContext.save()

            // re-import
            await loadFromJSON(into: modelContext, owner: currentUser)
            enforceStableIDs(in: modelContext)
            try modelContext.save()
            refreshData()
            return true
        } catch {
            print("Reset failed:", error)
            return false
        }
    }

    @MainActor
    func enforceStableIDs() {
        enforceStableIDs(in: modelContext)
    }


    @MainActor
    func refreshCatalogNow() async -> Bool {
        print("[Catalog] Manual refreshCatalogNow invoked")
        let before = allModels.count
        let devModeEnabled = UserDefaults.standard.bool(forKey: "devModeEnabled")
        let mode: ImportMode = devModeEnabled ? .replaceFromDeveloperJSON : .upsert
        await loadFromJSON(into: modelContext, owner: currentUser, mode: mode)
        let after = (try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? -1
        print("[Catalog] Manual refresh complete. Before=\(before), After=\(after)")
        refreshData()
        return true
    }

    @MainActor
    func createDeveloperSnapshot() {
        // Build lookup by model number
        let models = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        let flags: [SnapshotModelFlags] = models.map { m in
            SnapshotModelFlags(
                number: m.number,
                checked: m.checked,
                built: m.built,
                isFavorite: m.isFavorite,
                isWishlisted: m.isWishlisted,
                quantity: m.quantity
            )
        }
        let notes = ((try? modelContext.fetch(FetchDescriptor<ModelNote>())) ?? []).compactMap { n -> SnapshotNote? in
            // Map note modelId to number
            if let model = models.first(where: { $0.id == n.modelId }) {
                return SnapshotNote(number: model.number, text: n.text, timestamp: n.timestamp)
            }
            return nil
        }
        let photos = ((try? modelContext.fetch(FetchDescriptor<ModelPhoto>())) ?? []).compactMap { p -> SnapshotPhoto? in
            if let model = models.first(where: { $0.id == p.modelId }) {
                return SnapshotPhoto(number: model.number, imageData: p.imageData, timestamp: p.timestamp)
            }
            return nil
        }
        let snap = DeveloperSnapshot(createdAt: Date(), flags: flags, notes: notes, photos: photos)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: developerSnapshotKey)
            print("[DevMode] Snapshot saved: flags=\(flags.count), notes=\(notes.count), photos=\(photos.count)")
        }
    }

    @MainActor
    func restoreFromDeveloperSnapshot() async {
        guard let data = UserDefaults.standard.data(forKey: developerSnapshotKey),
              let snap = try? JSONDecoder().decode(DeveloperSnapshot.self, from: data) else {
            print("[DevMode] No snapshot to restore")
            return
        }

        // Refresh from default JSON first (merge/upsert)
        await loadFromJSON(into: modelContext, owner: currentUser, mode: .upsert)

        // Build lookups
        let models = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        let byNumber: [String: MetalModel] = Dictionary(uniqueKeysWithValues: models.map { ($0.number, $0) })

        // Restore flags
        for f in snap.flags {
            guard let m = byNumber[f.number] else { continue }
            m.checked = f.checked
            m.built = f.built
            m.isFavorite = f.isFavorite
            m.isWishlisted = f.isWishlisted
            m.quantity = f.quantity
        }

        // Restore notes: newest wins per model
        let existingNotes = (try? modelContext.fetch(FetchDescriptor<ModelNote>())) ?? []
        for note in existingNotes { modelContext.delete(note) }
        for n in snap.notes {
            guard let m = byNumber[n.number] else { continue }
            let newNote = ModelNote(modelId: m.id, text: n.text, timestamp: n.timestamp)
            modelContext.insert(newNote)
        }

        // Restore photos: remove existing and re-add from snapshot
        let existingPhotos = (try? modelContext.fetch(FetchDescriptor<ModelPhoto>())) ?? []
        for p in existingPhotos { modelContext.delete(p) }
        for p in snap.photos {
            guard let m = byNumber[p.number] else { continue }
            let newPhoto = ModelPhoto(modelId: m.id, imageData: p.imageData, timestamp: p.timestamp)
            modelContext.insert(newPhoto)
        }

        try? modelContext.save()
        refreshData()
        UserDefaults.standard.removeObject(forKey: developerSnapshotKey)
        print("[DevMode] Snapshot restored and cleared")
    }


    // MARK: - Photos / Notes

    // Photos: prevent same (modelId, checksum) from being added twice locally
    func addPhoto(for model: MetalModel, imageData: Data) {
        let finalData = compressImageData(imageData) ?? imageData
        guard finalData.count <= 1_000_000 else { return }

        let checksum = ModelPhoto.computeChecksum(data: finalData)
        let mid = model.id
        let cs  = checksum

        var fd = FetchDescriptor<ModelPhoto>(predicate: #Predicate { $0.modelId == mid && $0.checksum == cs })
        fd.fetchLimit = 1

        if (try? modelContext.fetch(fd).isEmpty) ?? true {
            let photo = ModelPhoto(modelId: mid, imageData: finalData)
            photo.checksum = checksum
            modelContext.insert(photo)
            try? modelContext.save()
            refreshData()
        }
    }

    @MainActor
    func reloadFromPersistentStore() {
        refreshData()
    }

    // Notes: single-per-model; update instead of adding a second row
    func addNote(for model: MetalModel, text: String) {
        let mid = model.id
        var fd = FetchDescriptor<ModelNote>(predicate: #Predicate { $0.modelId == mid })
        fd.fetchLimit = 1

        if let existing = try? modelContext.fetch(fd).first {
            existing.text = text
            existing.timestamp = Date()
        } else {
            modelContext.insert(ModelNote(modelId: mid, text: text))
        }
        try? modelContext.save()
        refreshData()
    }


    func deletePhoto(_ photo: ModelPhoto) {
        let id = photo.id
        let container = modelContainer
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = ModelContext(container)
            let fd = FetchDescriptor<ModelPhoto>(predicate: #Predicate { $0.id == id })
            if let p = try? ctx.fetch(fd).first {
                ctx.delete(p)
                try? ctx.save()
                Task { @MainActor in self.refreshData() }
            }
        }
    }

    func updateNote(for model: MetalModel, text: String) {
        if let existing = allNotes.first(where: { $0.modelId == model.id }) {
            existing.text = text
            existing.timestamp = Date()
        } else {
            addNote(for: model, text: text)
            return
        }
        saveContext()
    }

    // DataManager.swift — add near your Photos/Notes helpers
    func getPhotos(for model: MetalModel) -> [ModelPhoto] {
        allPhotos
            .filter { $0.modelId == model.id }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func getNote(for model: MetalModel) -> ModelNote? {
        allNotes.first { $0.modelId == model.id }
    }


    // MARK: - Fetch / Save / Cache

    private func fetchByID(_ id: UUID) throws -> MetalModel? {
        let fd = FetchDescriptor<MetalModel>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fd).first
    }

    private func refreshData() {
        allModels = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        allPhotos = (try? modelContext.fetch(FetchDescriptor<ModelPhoto>())) ?? []
        allNotes  = (try? modelContext.fetch(FetchDescriptor<ModelNote>())) ?? []
        invalidateCache()
        logDuplicateNumbers()
        print("[Catalog] refreshData: models=\(allModels.count), photos=\(allPhotos.count), notes=\(allNotes.count)")
    }

    private func saveContext() {
        do { try modelContext.save() } catch { print("Save error:", error) }
        refreshData()
    }

    func getCategorizedModels(searchText: String = "") -> [String: [MetalModel]] {
        cacheQueue.sync {
            let count = allModels.count
            let needsRefresh = cachedCategorizedModels.isEmpty
                || count != lastModelUpdateCount
                || (searchText != lastSearchText && !searchText.isEmpty)

            if needsRefresh {
                let source = searchText.isEmpty ? allModels : allModels.filter { $0.matches(searchText) }
                cachedCategorizedModels = Dictionary(grouping: source, by: { $0.category })
                lastModelUpdateCount = count
                lastSearchText = searchText
            }
            return cachedCategorizedModels
        }
    }

    private func invalidateCache() {
        cachedCategorizedModels = [:]
        lastModelUpdateCount = 0
        lastSearchText = ""
    }

    // MARK: - Dedup & Stable IDs

    private func score(_ m: MetalModel) -> Int {
        (m.checked ? 1 : 0) + (m.isFavorite ? 1 : 0) + (m.built ? 1 : 0) + m.quantity
    }

    private func enforceStableIDs(in context: ModelContext) {
        print("[Catalog] enforceStableIDs: start")
        let all = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        let groups = Dictionary(grouping: all, by: { $0.number })

        for (_, models) in groups {
            guard let number = models.first?.number else { continue }
            let targetID = MetalModel.stableID(for: number)

            // choose keeper (existing with stable id or best-scored)
            var keeper = models.first(where: { $0.id == targetID })
            if keeper == nil, let best = models.max(by: { score($0) < score($1) }) {
                let clone = MetalModel(
                    id: targetID,
                    backupIdentifier: best.backupIdentifier.isEmpty ? number : best.backupIdentifier,
                    checked: best.checked,
                    name: best.name,
                    number: best.number,
                    productCode: best.productCode,
                    character: best.character,
                    category: best.category,
                    firstReleaseYear: best.firstReleaseYear,
                    releaseCount: best.releaseCount,
                    series: best.series,
                    difficulty: best.difficulty,
                    sheets: best.sheets,
                    link: best.link,
                    instructionsLink: best.instructionsLink,
                    type: best.type,
                    status: best.status,
                    threeSixtyView: best.threeSixtyView,
                    modelDescription: best.modelDescription,
                    productImage: best.productImage,
                    isFavorite: best.isFavorite,
                    isWishlisted: best.isWishlisted,
                    quantity: best.quantity,
                    built: best.built
                )
                clone.owner = best.owner
                context.insert(clone)
                keeper = clone
            }
            guard let keep = keeper else { continue }

            for m in models where m.id != keep.id {
                // Merge user flags
                keep.checked      = keep.checked      || m.checked
                keep.isFavorite   = keep.isFavorite   || m.isFavorite
                keep.isWishlisted = keep.isWishlisted || m.isWishlisted
                keep.built        = keep.built        || m.built
                keep.quantity     = max(keep.quantity, m.quantity)

                // Move photos to keeper
                let sourceId = m.id
                let keepId   = keep.id

                // Move photos to keeper
                let otherPhotos = (try? context.fetch(
                    FetchDescriptor<ModelPhoto>(predicate: #Predicate { $0.modelId == sourceId })
                )) ?? []
                for p in otherPhotos { p.modelId = keepId }

                // Merge notes: newest text wins; otherwise re-home
                let otherNotes = (try? context.fetch(
                    FetchDescriptor<ModelNote>(predicate: #Predicate { $0.modelId == sourceId })
                )) ?? []
                var fd = FetchDescriptor<ModelNote>(
                    predicate: #Predicate { $0.modelId == keepId },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                fd.fetchLimit = 1
                var keepLatest = try? context.fetch(fd).first
                for n in otherNotes {
                    if let k = keepLatest {
                        if n.timestamp > k.timestamp { k.text = n.text; k.timestamp = n.timestamp }
                        context.delete(n)
                    } else {
                        n.modelId = keep.id
                        keepLatest = n
                    }
                }

                // Drop duplicate
                context.delete(m)
            }
        }
        print("[Catalog] enforceStableIDs: merging complete; saving…")
        try? context.save()
        print("[Catalog] enforceStableIDs: done")
    }


    private func logDuplicateNumbers() {
        let groups = Dictionary(grouping: allModels, by: { $0.number }).filter { $0.value.count > 1 }
        if !groups.isEmpty {
            print("⚠️ Duplicate numbers found (will be merged automatically):")
            for (num, list) in groups { print("   \(num): \(list.map{$0.id})") }
        }
    }
}

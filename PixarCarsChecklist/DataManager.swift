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
    @Published private(set) var favoriteModels: [MetalModel] = []
    @Published private(set) var wishlistedModels: [MetalModel] = []
    @Published private(set) var isReady = false
    private var photosLoaded = false
    private var modelsByID: [UUID: MetalModel] = [:]
    private var photosByModelID: [UUID: [ModelPhoto]] = [:]
    private var notesByModelID: [UUID: ModelNote] = [:]

    private static func appSupportFolder() -> URL {
        let root: URL
        do {
            root = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        } catch {
            print("Failed to resolve Application Support directory, using temporary storage:", error)
            root = FileManager.default.temporaryDirectory
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "PixarCarsChecklist"
        let folder = root.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func localStoreURL() -> URL {
        appSupportFolder().appendingPathComponent("default-v2.store", isDirectory: false)
    }

    private static func catalogOverridesURL() -> URL {
        appSupportFolder().appendingPathComponent("catalog-overrides.json", isDirectory: false)
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

    // Bump when the bundled catalog changes and should be merged into existing stores once.
    private let bundledCatalogVersion = 2026070301
    private let stableIDMigrationKey = "stableIDMigrationVersion"
    private let stableIDMigrationVersion = 1
    private let lastUpdatedKey = "catalogLastUpdated"
    private let lastRemoteCatalogRefreshDayKey = "lastRemoteCatalogRefreshDay"
    private let autoCatalogRefreshIntervalDays = 1

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
    private struct CatalogOverrideStore: Codable {
        var models: [String: CatalogEditPayload] = [:]
    }
    private struct CatalogImportItem {
        let baseNumber: String
        let payload: CatalogEditPayload
        let built: Bool
    }

    private enum ImportMode {
        case upsert
        case replaceFromDeveloperJSON
    }

    private func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modelsByNumber(_ models: [MetalModel]) -> [String: MetalModel] {
        var result: [String: MetalModel] = [:]
        for model in models {
            let key = normalizedKey(model.number)
            guard !key.isEmpty else { continue }

            if let existing = result[key] {
                result[key] = score(model) > score(existing) ? model : existing
            } else {
                result[key] = model
            }
        }
        return result
    }

    private func catalogItemsByNumber(_ items: [JSONModel]) -> [String: JSONModel] {
        var result: [String: JSONModel] = [:]
        for item in items {
            let key = normalizedKey(item.number)
            guard !key.isEmpty else { continue }
            result[key] = item
        }
        return result
    }

    private func readCatalogOverrides() -> [String: CatalogEditPayload] {
        let url = Self.catalogOverridesURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            let store = try JSONDecoder().decode(CatalogOverrideStore.self, from: data)
            return store.models.reduce(into: [:]) { result, entry in
                let key = normalizedKey(entry.key)
                guard !key.isEmpty else { return }
                result[key] = entry.value
            }
        } catch {
            print("[Catalog] Ignoring unreadable catalog overrides:", error)
            return [:]
        }
    }

    private func writeCatalogOverrides(_ overrides: [String: CatalogEditPayload]) {
        let url = Self.catalogOverridesURL()
        guard !overrides.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(CatalogOverrideStore(models: overrides))
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[Catalog] Failed to write catalog overrides:", error)
        }
    }

    private func putCatalogOverride(baseNumber: String, payload: CatalogEditPayload) {
        let key = normalizedKey(baseNumber).isEmpty ? normalizedKey(payload.number) : normalizedKey(baseNumber)
        guard !key.isEmpty else { return }
        var clean = payload
        clean.number = normalizedKey(clean.number)
        guard !clean.number.isEmpty else { return }
        var overrides = readCatalogOverrides()
        for (existingKey, existingPayload) in overrides {
            if existingKey == key ||
                existingKey == clean.number ||
                normalizedKey(existingPayload.number) == key ||
                normalizedKey(existingPayload.number) == clean.number {
                overrides.removeValue(forKey: existingKey)
            }
        }
        overrides[key] = clean
        writeCatalogOverrides(overrides)
    }

    private func removeCatalogOverrides(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        var overrides = readCatalogOverrides()
        for key in keys {
            overrides.removeValue(forKey: normalizedKey(key))
        }
        writeCatalogOverrides(overrides)
    }

    private func payload(from item: JSONModel) -> CatalogEditPayload {
        CatalogEditPayload(
            checked: item.checked,
            name: item.name,
            number: item.number,
            productCode: item.productCode,
            character: item.character,
            firstReleaseYear: item.firstReleaseYear,
            releaseCount: item.releaseCount,
            series: item.series,
            difficulty: item.difficulty,
            sheets: item.sheets,
            link: item.link,
            category: item.category,
            type: item.type,
            status: item.status,
            releaseDate: item.releaseDate,
            instructionsLink: item.instructionsLink,
            threeSixtyView: item.threeSixtyView,
            modelDescription: item.modelDescription,
            productImage: item.productImage
        )
    }

    private func catalogMetadataMatches(_ item: JSONModel, _ payload: CatalogEditPayload) -> Bool {
        normalizedKey(item.name) == normalizedKey(payload.name) &&
            normalizedKey(item.number) == normalizedKey(payload.number) &&
            normalizedKey(item.productCode) == normalizedKey(payload.productCode) &&
            normalizedKey(item.character) == normalizedKey(payload.character) &&
            item.firstReleaseYear == payload.firstReleaseYear &&
            item.releaseCount == payload.releaseCount &&
            normalizedKey(item.series) == normalizedKey(payload.series) &&
            normalizedKey(item.category) == normalizedKey(payload.category) &&
            item.difficulty == payload.difficulty &&
            item.sheets == payload.sheets &&
            normalizedKey(item.link) == normalizedKey(payload.link) &&
            normalizedKey(item.instructionsLink) == normalizedKey(payload.instructionsLink) &&
            normalizedKey(item.type) == normalizedKey(payload.type) &&
            normalizedKey(item.status) == normalizedKey(payload.status) &&
            normalizedKey(item.threeSixtyView) == normalizedKey(payload.threeSixtyView) &&
            normalizedKey(item.modelDescription) == normalizedKey(payload.modelDescription) &&
            normalizedKey(item.productImage) == normalizedKey(payload.productImage) &&
            normalizedKey(item.releaseDate) == normalizedKey(payload.releaseDate)
    }

    private func mergedCatalogImportItems(from remoteItems: [JSONModel]) -> [CatalogImportItem] {
        let overrides = readCatalogOverrides()
        var overrideKeysToClear = Set<String>()
        let remoteNumbers = Set(remoteItems.map { normalizedKey($0.number) }.filter { !$0.isEmpty })

        var imports: [CatalogImportItem] = remoteItems.compactMap { item in
            let baseNumber = normalizedKey(item.number)
            guard !baseNumber.isEmpty else { return nil }
            guard let override = overrides[baseNumber] else {
                return CatalogImportItem(baseNumber: baseNumber, payload: payload(from: item), built: item.built)
            }
            if catalogMetadataMatches(item, override) {
                overrideKeysToClear.insert(baseNumber)
                return CatalogImportItem(baseNumber: baseNumber, payload: payload(from: item), built: item.built)
            }
            return CatalogImportItem(baseNumber: baseNumber, payload: override, built: false)
        }

        for (baseNumber, payload) in overrides where !remoteNumbers.contains(baseNumber) {
            if remoteItems.contains(where: { catalogMetadataMatches($0, payload) }) {
                overrideKeysToClear.insert(baseNumber)
            } else {
                imports.append(CatalogImportItem(baseNumber: baseNumber, payload: payload, built: false))
            }
        }

        removeCatalogOverrides(overrideKeysToClear)
        return imports
    }

    private let catalogNumberAliases: [String: String] = [:]

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
                print("Failed to open local store after reset; using in-memory fallback:", error)
                let fallbackConfig = ModelConfiguration(
                    "RecoveredInMemoryStore",
                    schema: Self.appSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                container = try! ModelContainer(for: Self.appSchema, configurations: [fallbackConfig])
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

        Task { @MainActor in
            let existingModelCount = (try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? 0

            if existingModelCount == 0 {
                _ = await self.initializePersistentStorage()
                self.refreshData()
                self.isReady = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                _ = await self.refreshDefaultCatalogIfNeeded()
            } else {
                self.refreshData()
                self.isReady = true

                // Let the app render from the existing local store before doing a bundled
                // catalog maintenance pass after an app update.
                try? await Task.sleep(nanoseconds: 500_000_000)
                let didChange = await self.initializePersistentStorage()
                if didChange {
                    self.refreshData(loadPhotos: self.photosLoaded)
                }
                _ = await self.refreshDefaultCatalogIfNeeded()
            }
        }
    }


    // MARK: - First run & every-run seeding

    @discardableResult
    private func initializePersistentStorage() async -> Bool {
        print("[Catalog] initializePersistentStorage: starting")
        let modelCount = (try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? 0
        let catalogVersion = appMetaIntValue(for: "catalogVersion", in: modelContext)
        let stableMigrationVersion = appMetaIntValue(for: stableIDMigrationKey, in: modelContext)
        let needsBundledImport = modelCount == 0 || bundledCatalogVersion > catalogVersion
        let needsStableIDMigration = stableMigrationVersion < stableIDMigrationVersion
        var didChange = false

        if needsBundledImport {
            if modelCount == 0 {
                print("[Catalog] Store empty: seeding from bundled JSON")
            } else {
                print("[Catalog] Bundled catalog version \(bundledCatalogVersion) is newer than stored version \(catalogVersion)")
            }

            let imported = await loadFromJSON(into: modelContext, owner: currentUser, allowRemote: false)
            if imported {
                print("[Catalog] Bundled import complete. Model count now: \((try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
                if needsStableIDMigration {
                    enforceStableIDs(in: modelContext)
                }
                setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
                setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
                didChange = true
            } else {
                print("[Catalog] Bundled import failed; leaving catalog metadata unchanged")
            }
        } else {
            print("[Catalog] Bundled catalog already imported; skipping startup import")
        }

        if !needsBundledImport && needsStableIDMigration {
            print("[Catalog] Running one-time stable ID migration")
            enforceStableIDs(in: modelContext)
            setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
            didChange = true
        }

        if didChange {
            try? modelContext.save()
            print("[Catalog] Saved context after startup maintenance")
        }

        return didChange
    }

    private func appMetaIntValue(for key: String, in context: ModelContext) -> Int {
        let fd = FetchDescriptor<AppMeta>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(fd).first?.intValue) ?? 0
    }

    private func setAppMetaIntValue(_ value: Int, for key: String, in context: ModelContext) {
        let fd = FetchDescriptor<AppMeta>(predicate: #Predicate { $0.key == key })
        let existing = try? context.fetch(fd).first
        let meta = existing ?? AppMeta(key: key, intValue: 0)
        meta.intValue = value
        if existing == nil {
            context.insert(meta)
        }
    }

    private func currentEpochDay() -> Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }

    @MainActor
    private func refreshDefaultCatalogIfNeeded() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: "devModeEnabled") else { return false }

        let today = currentEpochDay()
        let lastRefreshDay = appMetaIntValue(for: lastRemoteCatalogRefreshDayKey, in: modelContext)
        if lastRefreshDay > 0 && today - lastRefreshDay < autoCatalogRefreshIntervalDays {
            return true
        }

        let previousRemoteUpdate = UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date
        let imported = await loadFromJSON(into: modelContext, owner: currentUser, mode: .upsert, allowRemote: true)
        let currentRemoteUpdate = UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date
        guard imported, currentRemoteUpdate != previousRemoteUpdate else { return false }

        enforceStableIDs(in: modelContext)
        setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
        setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
        setAppMetaIntValue(today, for: lastRemoteCatalogRefreshDayKey, in: modelContext)
        try? modelContext.save()
        refreshData(loadPhotos: photosLoaded)
        return true
    }

    @MainActor
    func refreshCatalogForAppActivation() async -> Bool {
        await refreshDefaultCatalogIfNeeded()
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
        let sheets: Double?
        let link: String
        let instructionsLink: String
        let type: String
        let status: String
        let threeSixtyView: String
        let modelDescription: String
        let productImage: String
        let releaseDate: String
        let built: Bool

        enum CodingKeys: String, CodingKey {
            case checked, name, number, productCode, character, category, firstReleaseYear, releaseCount, series
            case difficulty, sheets, link, instructionsLink, type, status, built
            case threeSixtyView = "360View"
            case modelDescription = "description"
            case productImage = "productimage"
            case releaseDate
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
            sheets = try? c.decode(Double.self, forKey: .sheets)
            link = (try? c.decode(String.self, forKey: .link)) ?? ""
            instructionsLink = (try? c.decode(String.self, forKey: .instructionsLink)) ?? ""
            type = (try? c.decode(String.self, forKey: .type)) ?? ""
            status = (try? c.decode(String.self, forKey: .status)) ?? ""
            built = (try? c.decode(Bool.self, forKey: .built)) ?? false
            threeSixtyView = (try? c.decode(String.self, forKey: .threeSixtyView)) ?? ""
            modelDescription = (try? c.decode(String.self, forKey: .modelDescription)) ?? ""
            productImage = (try? c.decode(String.self, forKey: .productImage)) ?? ""
            releaseDate = (try? c.decode(String.self, forKey: .releaseDate)) ?? ""
        }
    }



    // Upsert-from-JSON: never overwrites user flags (checked/built/favorite/quantity/owner)
    @discardableResult
    private func loadFromJSON(into context: ModelContext, owner: User, mode: ImportMode = .upsert, allowRemote: Bool = false) async -> Bool {
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
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
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

        if allowRemote {
            do {
                let data = try await fetchRemoteData()
                print("[Catalog] Remote fetch succeeded. Beginning upsert")
                switch mode {
                case .upsert:
                    try await upsert(from: data, into: context, owner: owner)
                case .replaceFromDeveloperJSON:
                    try await replaceCatalog(from: data, into: context, owner: owner)
                }
                UserDefaults.standard.set(Date(), forKey: lastUpdatedKey)
                print("✅ [Catalog] Loaded from remote and upserted. Pre-count: \(preCount), Post-count: \((try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
                return true
            } catch {
                print("⚠️ [Catalog] Remote fetch failed: \(error) — falling back to bundle")
            }
        } else {
            print("[Catalog] Skipping remote fetch for fast local startup")
        }

        do {
            // Fallback to bundled file
            let data = try loadBundledData()
            print("[Catalog] Loaded bundled JSON (bytes: \(data.count)). Beginning upsert")
            switch mode {
            case .upsert:
                try await upsert(from: data, into: context, owner: owner)
            case .replaceFromDeveloperJSON:
                try await replaceCatalog(from: data, into: context, owner: owner)
            }
            print("✅ [Catalog] Loaded from bundle and upserted. Pre-count: \(preCount), Post-count: \((try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1)")
            return true
        } catch {
            print("❌ [Catalog] JSON import failed: \(error)")
            return false
        }
    }

    private func applyCatalogMetadata(from jm: JSONModel, to model: MetalModel, number: String) -> Bool {
        applyCatalogMetadata(from: payload(from: jm), to: model, number: number)
    }

    private func applyCatalogMetadata(from payload: CatalogEditPayload, to model: MetalModel, number: String) -> Bool {
        var didChange = false

        func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<MetalModel, T>, _ value: T) {
            if model[keyPath: keyPath] != value {
                model[keyPath: keyPath] = value
                didChange = true
            }
        }

        assign(\.name, payload.name)
        assign(\.number, number)
        assign(\.productCode, payload.productCode)
        assign(\.character, payload.character)
        assign(\.firstReleaseYear, payload.firstReleaseYear)
        assign(\.releaseCount, payload.releaseCount)
        assign(\.series, payload.series)
        assign(\.category, payload.category)
        assign(\.difficulty, payload.difficulty)
        assign(\.sheets, payload.sheets)
        assign(\.link, payload.link)
        assign(\.instructionsLink, payload.instructionsLink)
        assign(\.type, payload.type)
        assign(\.status, payload.status)
        assign(\.threeSixtyView, payload.threeSixtyView)
        assign(\.modelDescription, payload.modelDescription)
        assign(\.productImage, payload.productImage)
        assign(\.releaseDate, payload.releaseDate)

        return didChange
    }

    // Helper to keep the original upsert logic intact
    private func upsert(from data: Data, into context: ModelContext, owner: User) async throws {
        let decoder = JSONDecoder()
        print("[Catalog] Upsert: decoding JSON (bytes: \(data.count))…")
        let remoteItems = try decoder.decode([JSONModel].self, from: data)
        let items = mergedCatalogImportItems(from: remoteItems)
        print("[Catalog] Upsert: decoded items: \(remoteItems.count), importing: \(items.count)")

        try migrateCatalogNumberAliases(in: context)

        // Existing models keyed by number
        let existing = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        var byNumber = modelsByNumber(existing)
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        let existingCount = existing.count
        var updated = 0
        var inserted = 0
        var unchanged = 0

        for item in items {
            let payload = item.payload
            let number = normalizedKey(payload.number)
            guard !number.isEmpty else { continue }

            if let m = byNumber[number] ?? byID[MetalModel.stableID(for: item.baseNumber)] ?? byNumber[item.baseNumber] {
                if applyCatalogMetadata(from: payload, to: m, number: number) {
                    updated += 1
                } else {
                    unchanged += 1
                }
                byNumber[number] = m
                byID[m.id] = m
            } else {
                inserted += 1
                // Insert new row
                let model = MetalModel(
                    id: MetalModel.stableID(for: item.baseNumber),
                    backupIdentifier: number,
                    checked: payload.checked,
                    name: payload.name,
                    number: number,
                    productCode: payload.productCode,
                    character: payload.character,
                    category: payload.category,
                    firstReleaseYear: payload.firstReleaseYear,
                    releaseCount: payload.releaseCount,
                    series: payload.series,
                    difficulty: payload.difficulty,
                    sheets: payload.sheets,
                    link: payload.link,
                    instructionsLink: payload.instructionsLink,
                    type: payload.type,
                    status: payload.status,
                    threeSixtyView: payload.threeSixtyView,
                    modelDescription: payload.modelDescription,
                    productImage: payload.productImage,
                    releaseDate: payload.releaseDate,
                    isFavorite: false,
                    isWishlisted: false,
                    quantity: payload.checked ? 1 : 0,
                    built: item.built
                )
                model.owner = owner
                context.insert(model)
                byNumber[number] = model
                byID[model.id] = model
            }
        }
        print("[Catalog] Upsert: existing=\(existingCount), updated=\(updated), unchanged=\(unchanged), inserted=\(inserted)")
        if updated > 0 || inserted > 0 {
            try context.save()
        }
        let postCount = (try? context.fetchCount(FetchDescriptor<MetalModel>())) ?? -1
        print("[Catalog] Upsert: save complete. Total models now: \(postCount)")
    }

    // Replace-mode import used by Developer Mode: keeps only models present in the JSON,
    // but preserves user flags when numbers/backupIdentifiers match.
    private func replaceCatalog(from data: Data, into context: ModelContext, owner: User) async throws {
        let decoder = JSONDecoder()
        let remoteItems = try decoder.decode([JSONModel].self, from: data)
        let items = mergedCatalogImportItems(from: remoteItems)

        try migrateCatalogNumberAliases(in: context)

        // Build lookup of desired numbers from JSON
        let desiredNumbers = Set(items.map { normalizedKey($0.payload.number) }.filter { !$0.isEmpty })

        // Fetch existing models
        let existingModels = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        var existingByNumber = modelsByNumber(existingModels)
        var existingByID = Dictionary(uniqueKeysWithValues: existingModels.map { ($0.id, $0) })

        // 1) Delete any existing models whose number is NOT in the dev JSON
        for model in existingModels where !desiredNumbers.contains(normalizedKey(model.number)) {
            context.delete(model)
        }

        // 2) Upsert for items in JSON, preserving user flags on matches
        for item in items {
            let payload = item.payload
            let number = normalizedKey(payload.number)
            guard !number.isEmpty else { continue }

            if let existing = existingByNumber[number] ?? existingByID[MetalModel.stableID(for: item.baseNumber)] ?? existingByNumber[item.baseNumber] {
                // Update catalog fields, preserve user flags
                _ = applyCatalogMetadata(from: payload, to: existing, number: number)
                existingByNumber[number] = existing
                existingByID[existing.id] = existing
            } else {
                // Insert new row with user flags defaulted based on JSON
                let model = MetalModel(
                    id: MetalModel.stableID(for: item.baseNumber),
                    backupIdentifier: number,
                    checked: payload.checked,
                    name: payload.name,
                    number: number,
                    productCode: payload.productCode,
                    character: payload.character,
                    category: payload.category,
                    firstReleaseYear: payload.firstReleaseYear,
                    releaseCount: payload.releaseCount,
                    series: payload.series,
                    difficulty: payload.difficulty,
                    sheets: payload.sheets,
                    link: payload.link,
                    instructionsLink: payload.instructionsLink,
                    type: payload.type,
                    status: payload.status,
                    threeSixtyView: payload.threeSixtyView,
                    modelDescription: payload.modelDescription,
                    productImage: payload.productImage,
                    releaseDate: payload.releaseDate,
                    isFavorite: false,
                    isWishlisted: false,
                    quantity: payload.checked ? 1 : 0,
                    built: item.built
                )
                model.owner = owner
                context.insert(model)
                existingByNumber[number] = model
                existingByID[model.id] = model
            }
        }

        // Save and refresh caches
        try context.save()
    }

    private func migrateCatalogNumberAliases(in context: ModelContext) throws {
        guard !catalogNumberAliases.isEmpty else { return }

        let models = (try? context.fetch(FetchDescriptor<MetalModel>())) ?? []
        guard !models.isEmpty else { return }

        var byNumber = modelsByNumber(models)
        var changed = false

        for (oldNumber, newNumber) in catalogNumberAliases {
            guard let oldModel = byNumber[oldNumber] else { continue }

            if let newModel = byNumber[newNumber], newModel !== oldModel {
                newModel.checked = newModel.checked || oldModel.checked
                newModel.isFavorite = newModel.isFavorite || oldModel.isFavorite
                newModel.isWishlisted = newModel.isWishlisted || oldModel.isWishlisted
                newModel.quantity = max(newModel.quantity, oldModel.quantity)
                newModel.built = newModel.built || oldModel.built

                let oldId = oldModel.id
                let newId = newModel.id
                let oldNotes = (try? context.fetch(
                    FetchDescriptor<ModelNote>(predicate: #Predicate { $0.modelId == oldId })
                )) ?? []
                let oldPhotos = (try? context.fetch(
                    FetchDescriptor<ModelPhoto>(predicate: #Predicate { $0.modelId == oldId })
                )) ?? []

                for note in oldNotes {
                    note.modelId = newModel.id
                }
                for photo in oldPhotos {
                    photo.modelId = newId
                }

                context.delete(oldModel)
                byNumber.removeValue(forKey: oldNumber)
                changed = true
            } else {
                oldModel.number = newNumber
                oldModel.backupIdentifier = newNumber
                byNumber.removeValue(forKey: oldNumber)
                byNumber[newNumber] = oldModel
                changed = true
            }
        }

        if changed {
            try context.save()
        }
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

    func generateWishlistShareHTML() -> String {
        let items = allModels
            .filter { $0.isWishlisted }
            .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        guard !items.isEmpty else { return "" }

        func escape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        let cards = items.map { model -> String in
            let number = escape(model.number)
            let name = escape(model.name)
            let link = escape(model.link.isEmpty ? model.instructionsLink : model.link)
            let image = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageHTML: String
            if image.lowercased().hasPrefix("http") {
                imageHTML = "<img src=\"\(escape(image))\" alt=\"\(name)\">"
            } else {
                imageHTML = "<div class=\"image placeholder\">No image</div>"
            }

            let linkHTML = link.isEmpty ? "" : "<a href=\"\(link)\">Model page</a>"
            return """
            <article class="card">
              <div class="image">\(imageHTML)</div>
              <div class="meta">
                <div class="number">\(number)</div>
                <h2>\(name)</h2>
                \(linkHTML)
              </div>
            </article>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Pixar Cars Wishlist</title>
          <style>
            :root { color-scheme: light; --accent: #66d12d; --ink: #182015; --muted: #5e695a; --line: #d8e0d4; --paper: #f6f8f4; }
            * { box-sizing: border-box; }
            body { margin: 0; font: 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: var(--ink); background: var(--paper); }
            header { padding: 28px 24px 18px; background: #ffffff; border-bottom: 1px solid var(--line); }
            h1 { margin: 0 0 6px; font-size: 30px; letter-spacing: 0; }
            .summary { color: var(--muted); }
            main { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px; padding: 18px; }
            .card { background: #ffffff; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
            .image { height: 170px; display: flex; align-items: center; justify-content: center; background: #eef3eb; }
            .image img { width: 100%; height: 100%; object-fit: contain; padding: 12px; }
            .placeholder { color: var(--muted); font-size: 13px; }
            .meta { padding: 14px; }
            .number { color: var(--accent); font-weight: 700; font-size: 13px; margin-bottom: 5px; }
            h2 { margin: 0 0 10px; font-size: 18px; line-height: 1.25; }
            a { color: #276b18; font-weight: 600; text-decoration: none; }
          </style>
        </head>
        <body>
          <header>
            <h1>Pixar Cars Wishlist</h1>
            <div class="summary">\(items.count) model\(items.count == 1 ? "" : "s")</div>
          </header>
          <main>
        \(cards)
          </main>
        </body>
        </html>
        """
    }



    // ADDED THESE

    // Add near other public helpers
    @MainActor
    func handleJSONUpdates() async {
        let imported = await loadFromJSON(into: modelContext, owner: currentUser, allowRemote: true)   // additive import
        guard imported else { return }
        enforceStableIDs(in: modelContext)
        setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
        setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
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
            photosLoaded = false
            allPhotos = []
            photosByModelID = [:]
            try? FileManager.default.removeItem(at: Self.catalogOverridesURL())

            // re-import
            let imported = await loadFromJSON(into: modelContext, owner: currentUser, allowRemote: false)
            guard imported else { return false }
            enforceStableIDs(in: modelContext)
            setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
            setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
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
        let imported = await loadFromJSON(into: modelContext, owner: currentUser, mode: mode, allowRemote: true)
        guard imported else { return false }
        enforceStableIDs(in: modelContext)
        setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
        setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
        try? modelContext.save()
        let after = (try? modelContext.fetchCount(FetchDescriptor<MetalModel>())) ?? -1
        print("[Catalog] Manual refresh complete. Before=\(before), After=\(after)")
        refreshData()
        return true
    }

    @MainActor
    func applyCatalogEdit(to model: MetalModel, payload: CatalogEditPayload) {
        let originalNumber = model.number
        let cleanNumber = payload.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else { return }

        model.backupIdentifier = cleanNumber
        model.name = payload.name
        model.number = cleanNumber
        model.productCode = payload.productCode
        model.character = payload.character
        model.firstReleaseYear = payload.firstReleaseYear
        model.releaseCount = payload.releaseCount
        model.series = payload.series
        model.category = payload.category
        model.difficulty = payload.difficulty
        model.sheets = payload.sheets
        model.link = payload.link
        model.instructionsLink = payload.instructionsLink
        model.type = payload.type
        model.status = payload.status
        model.threeSixtyView = payload.threeSixtyView
        model.modelDescription = payload.modelDescription
        model.productImage = payload.productImage
        model.releaseDate = payload.releaseDate

        putCatalogOverride(baseNumber: originalNumber, payload: payload)
        try? modelContext.save()
        refreshData(loadPhotos: photosLoaded)
    }

    @MainActor
    func applyCatalogCreate(_ payload: CatalogEditPayload) {
        let cleanNumber = payload.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else { return }

        let existingModels = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        if let existing = modelsByNumber(existingModels)[cleanNumber] {
            applyCatalogEdit(to: existing, payload: payload)
            return
        }

        let model = MetalModel(
            id: MetalModel.stableID(for: cleanNumber),
            backupIdentifier: cleanNumber,
            checked: payload.checked,
            name: payload.name,
            number: cleanNumber,
            productCode: payload.productCode,
            character: payload.character,
            category: payload.category,
            firstReleaseYear: payload.firstReleaseYear,
            releaseCount: payload.releaseCount,
            series: payload.series,
            difficulty: payload.difficulty,
            sheets: payload.sheets,
            link: payload.link,
            instructionsLink: payload.instructionsLink,
            type: payload.type,
            status: payload.status,
            threeSixtyView: payload.threeSixtyView,
            modelDescription: payload.modelDescription,
            productImage: payload.productImage,
            releaseDate: payload.releaseDate,
            isFavorite: false,
            isWishlisted: false,
            quantity: payload.checked ? 1 : 0,
            built: false,
            owner: currentUser
        )
        modelContext.insert(model)
        putCatalogOverride(baseNumber: cleanNumber, payload: payload)
        try? modelContext.save()
        refreshData(loadPhotos: photosLoaded)
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
        let imported = await loadFromJSON(into: modelContext, owner: currentUser, mode: .upsert, allowRemote: false)
        guard imported else { return }

        // Build lookups
        let models = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        let byNumber = modelsByNumber(models)

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

        setAppMetaIntValue(bundledCatalogVersion, for: "catalogVersion", in: modelContext)
        setAppMetaIntValue(stableIDMigrationVersion, for: stableIDMigrationKey, in: modelContext)
        try? modelContext.save()
        refreshData(loadPhotos: photosLoaded)
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
            refreshData(loadPhotos: true)
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
                Task { @MainActor in self.refreshData(loadPhotos: true) }
            }
        }
    }

    func updateNote(for model: MetalModel, text: String) {
        if let existing = notesByModelID[model.id] {
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
        if photosLoaded {
            return photosByModelID[model.id] ?? []
        }

        let mid = model.id
        let descriptor = FetchDescriptor<ModelPhoto>(
            predicate: #Predicate { $0.modelId == mid },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getNote(for model: MetalModel) -> ModelNote? {
        notesByModelID[model.id]
    }

    func model(for id: UUID) -> MetalModel? {
        modelsByID[id]
    }


    // MARK: - Fetch / Save / Cache

    private func fetchByID(_ id: UUID) throws -> MetalModel? {
        let fd = FetchDescriptor<MetalModel>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(fd).first
    }

    @MainActor
    func loadPhotosIfNeeded() {
        guard !photosLoaded else { return }
        refreshPhotos()
    }

    @MainActor
    func refreshPhotos() {
        let descriptor = FetchDescriptor<ModelPhoto>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        allPhotos = (try? modelContext.fetch(descriptor)) ?? []
        photosByModelID = Dictionary(grouping: allPhotos, by: { $0.modelId })
        photosLoaded = true
    }

    private func refreshData(loadPhotos: Bool = false) {
        allModels = (try? modelContext.fetch(FetchDescriptor<MetalModel>())) ?? []
        modelsByID.removeAll(keepingCapacity: true)
        for model in allModels {
            modelsByID[model.id] = model
        }
        favoriteModels = allModels.filter { $0.isFavorite }
        wishlistedModels = allModels.filter { $0.isWishlisted }

        if loadPhotos || photosLoaded {
            refreshPhotos()
        }
        allNotes  = (try? modelContext.fetch(FetchDescriptor<ModelNote>())) ?? []
        notesByModelID.removeAll(keepingCapacity: true)
        for note in allNotes {
            if let existing = notesByModelID[note.modelId] {
                if note.timestamp > existing.timestamp {
                    notesByModelID[note.modelId] = note
                }
            } else {
                notesByModelID[note.modelId] = note
            }
        }
        invalidateCache()
        #if DEBUG
        logDuplicateNumbers()
        print("[Catalog] refreshData: models=\(allModels.count), photos=\(allPhotos.count), notes=\(allNotes.count)")
        #endif
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

import Foundation
import SwiftData
import Zip

@MainActor
final class BackupManager: ObservableObject {
    @Published var isCreatingBackup = false
    @Published var backupProgress: Double = 0
    @Published var lastBackupError: String?
    @Published var lastRestoreError: String?

    private let fileManager = FileManager.default
    private let tempDirectory = FileManager.default.temporaryDirectory

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    nonisolated private static func safeTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: Date())
    }

    // MARK: - Backup Creation

    func createBackup(context: ModelContext) async throws -> URL {
        isCreatingBackup = true
        defer { isCreatingBackup = false }
        backupProgress = 0
        lastBackupError = nil

        let tempDir = tempDirectory
        let fm = fileManager
        let encoder = jsonEncoder

        let resultURL: URL = try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    // Create a unique directory for this backup
                    let backupDir = tempDir.appendingPathComponent("PixarCarsBackup-\(BackupManager.safeTimestamp())")
                    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

                    // Create subdirectories for photos
                    let photosDir = backupDir.appendingPathComponent("photos")
                    try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)

                    // Export all data (reuse existing helpers)
                    let userModelsURL = try await self.exportUserModels(context: context, to: backupDir)
                    let photosURL = try await self.exportPhotos(context: context, to: backupDir)
                    let notesURL = try await self.exportNotes(context: context, to: backupDir)
                    _ = (userModelsURL, photosURL, notesURL)

                    // Create manifest (reuse existing code)
                    let manifest = BackupManifest(
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        createdDate: Date(),
                        modelCount: try context.fetchCount(FetchDescriptor<MetalModel>()),
                        photoCount: try context.fetchCount(FetchDescriptor<ModelPhoto>()),
                        noteCount: try context.fetchCount(FetchDescriptor<ModelNote>())
                    )
                    let manifestData = try encoder.encode(manifest)
                    try manifestData.write(to: backupDir.appendingPathComponent("manifest.json"))

                    // Zip the backup
                    let zipFile = tempDir.appendingPathComponent("PixarCarsBackup-\(BackupManager.safeTimestamp()).zip")
                    try Zip.zipFiles(paths: [backupDir], zipFilePath: zipFile, password: nil, progress: { progress in
                        DispatchQueue.main.async { self.backupProgress = progress }
                    })

                    // Clean up the temporary directory
                    try fm.removeItem(at: backupDir)

                    continuation.resume(returning: zipFile)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return resultURL
    }

    private func exportUserModels(context: ModelContext, to directory: URL) async throws -> URL {
        let models = try context.fetch(FetchDescriptor<MetalModel>())
        let userData = models.map { model in
            UserModelData(
                backupIdentifier: model.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                checked: model.checked,
                built: model.built,
                isFavorite: model.isFavorite,
                isWishlisted: model.isWishlisted,
                quantity: model.quantity
            )
        }

        let data = try jsonEncoder.encode(userData)
        let fileURL = directory.appendingPathComponent("user_models.json")
        try data.write(to: fileURL)
        return fileURL
    }

    private func exportPhotos(context: ModelContext, to directory: URL) async throws -> URL {
        let photos = try context.fetch(FetchDescriptor<ModelPhoto>())
        let photosDir = directory.appendingPathComponent("photos")
        try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let models = try context.fetch(FetchDescriptor<MetalModel>())
        let idToBackup = Dictionary(uniqueKeysWithValues: models.map {
            ($0.id, $0.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines))
        })

        var photoMetadata: [PhotoMetadata] = []

        for photo in photos {
            guard let backupId = idToBackup[photo.modelId], !backupId.isEmpty else { continue }
            let filename = "\(photo.id.uuidString).jpg"
            try photo.imageData.write(to: photosDir.appendingPathComponent(filename))

            photoMetadata.append(PhotoMetadata(
                id: photo.id,
                backupIdentifier: backupId,
                timestamp: photo.timestamp,
                filename: filename
            ))
        }

        let metadataData = try jsonEncoder.encode(photoMetadata)
        let metadataFile = directory.appendingPathComponent("photos_metadata.json")
        try metadataData.write(to: metadataFile)
        return metadataFile
    }


    private func exportNotes(context: ModelContext, to directory: URL) async throws -> URL {
        let notes = try context.fetch(FetchDescriptor<ModelNote>())
        let models = try context.fetch(FetchDescriptor<MetalModel>())
        let modelIdToBackupId = Dictionary(uniqueKeysWithValues: models.map {
            ($0.id, $0.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines))
        })

        let noteData: [NoteExportData] = notes.compactMap { note in
            let backupId = modelIdToBackupId[note.modelId] ?? ""
            guard !backupId.isEmpty else { return nil }
            return NoteExportData(
                id: note.id,
                modelBackupIdentifier: backupId,
                text: note.text,
                timestamp: note.timestamp
            )
        }

        let notesData = try jsonEncoder.encode(noteData)
        let fileURL = directory.appendingPathComponent("notes.json")
        try notesData.write(to: fileURL)
        return fileURL
    }

    struct NoteExportData: Codable {
        let id: UUID
        let modelBackupIdentifier: String
        let text: String
        let timestamp: Date
    }

    // MARK: - Restore

    // MARK: - Restore
    func restoreBackup(from zipFile: URL, context: ModelContext) async throws {
        // First ensure we have access to the file
        guard zipFile.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "BackupManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "No access to the backup file"])
        }
        defer { zipFile.stopAccessingSecurityScopedResource() }

        let unzipDir = tempDirectory.appendingPathComponent("Restore-\(Date().ISO8601Format())")
        defer { try? fileManager.removeItem(at: unzipDir) }
        try Zip.unzipFile(zipFile, destination: unzipDir, overwrite: true, password: nil, progress: nil)

        // Find the actual backup directory
        let contents = try fileManager.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
        let backupDir = contents.first {
            $0.lastPathComponent.hasPrefix("PixarCarsBackup-") ||
            $0.lastPathComponent.hasPrefix("MetalEarthBackup-")
        } ?? unzipDir

        // Load backup data
        let backupUserModels = try loadUserModels(from: backupDir)
        let backupPhotos = try loadPhotos(from: backupDir)
        let backupNotes = try loadNotes(from: backupDir)

        // Get current models
        let currentModels = try context.fetch(FetchDescriptor<MetalModel>())

        // Build lookup: backupIdentifier (trimmed, non-empty) -> MetalModel
        let backupIdToModel: [String: MetalModel] = Dictionary(
            uniqueKeysWithValues: currentModels.compactMap { m in
                let key = m.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                return key.isEmpty ? nil : (key, m)
            }
        )

        // Build lookup: backupIdentifier (trimmed) -> exported user flags
        let backupUserModelsByID: [String: UserModelData] = Dictionary(
            uniqueKeysWithValues: backupUserModels.map { ($0.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines), $0) }
        )

        // Restore flags (only when there is an exact backupIdentifier match)
        for model in currentModels {
            let key = model.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if let backupData = backupUserModelsByID[key] {
                model.checked = backupData.checked
                model.built = backupData.built
                model.isFavorite = backupData.isFavorite
                model.isWishlisted = backupData.isWishlisted
                model.quantity = backupData.quantity
            }
        }

        // Remove existing photos & notes (we'll re-insert from backup)
        let existingPhotos = try context.fetch(FetchDescriptor<ModelPhoto>())
        existingPhotos.forEach { context.delete($0) }

        let existingNotes = try context.fetch(FetchDescriptor<ModelNote>())
        existingNotes.forEach { context.delete($0) }

        // Restore photos
        for photo in backupPhotos {
            let key = photo.backupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let model = backupIdToModel[key], !photo.imageData.isEmpty else { continue }
            let newPhoto = ModelPhoto(modelId: model.id, imageData: photo.imageData, timestamp: photo.timestamp)
            context.insert(newPhoto)
        }

        // Restore notes
        for note in backupNotes {
            let key = note.modelBackupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let model = backupIdToModel[key] else { continue }
            let newNote = ModelNote(modelId: model.id, text: note.text, timestamp: note.timestamp)
            context.insert(newNote)
        }

        try context.save()
        try fileManager.removeItem(at: unzipDir)
    }


    private func loadUserModels(from directory: URL) throws -> [UserModelData] {
        let fileURL = directory.appendingPathComponent("user_models.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "BackupManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "user_models.json not found in backup"])
        }
        let data = try Data(contentsOf: fileURL)
        return try jsonDecoder.decode([UserModelData].self, from: data)
    }

    private func loadPhotos(from directory: URL) throws -> [PhotoImport] {
        let metadataURL = directory.appendingPathComponent("photos_metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw NSError(domain: "BackupManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "photos_metadata.json not found in backup"])
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try jsonDecoder.decode([PhotoMetadata].self, from: metadataData)

        let photosDir = directory.appendingPathComponent("photos")
        var photos = [PhotoImport]()

        for meta in metadata {
            let imageURL = photosDir.appendingPathComponent(meta.filename)
            guard fileManager.fileExists(atPath: imageURL.path) else {
                continue // Skip missing photos but don't fail the whole restore
            }
            let imageData = try Data(contentsOf: imageURL)
            photos.append(PhotoImport(
                backupIdentifier: meta.backupIdentifier,
                imageData: imageData,
                timestamp: meta.timestamp
            ))
        }

        return photos
    }

    private func loadNotes(from directory: URL) throws -> [NoteImportData] {
        let fileURL = directory.appendingPathComponent("notes.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "BackupManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "notes.json not found in backup"])
        }
        let data = try Data(contentsOf: fileURL)
        return try jsonDecoder.decode([NoteImportData].self, from: data)
    }

    struct NoteImportData: Codable {  // Changed from just a struct to Codable
        let modelBackupIdentifier: String
        let text: String
        let timestamp: Date
    }

    // MARK: - Data Structures

    struct UserModelData: Codable {
        let backupIdentifier: String
        let checked: Bool
        let built: Bool
        let isFavorite: Bool
        let isWishlisted: Bool
        let quantity: Int

        enum CodingKeys: String, CodingKey {
            case backupIdentifier
            case checked
            case built
            case isFavorite
            case isWishlisted
            case quantity
        }

        init(backupIdentifier: String, checked: Bool, built: Bool, isFavorite: Bool, isWishlisted: Bool, quantity: Int) {
            self.backupIdentifier = backupIdentifier
            self.checked = checked
            self.built = built
            self.isFavorite = isFavorite
            self.isWishlisted = isWishlisted
            self.quantity = quantity
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            backupIdentifier = try c.decode(String.self, forKey: .backupIdentifier)
            checked = (try? c.decode(Bool.self, forKey: .checked)) ?? false
            built = (try? c.decode(Bool.self, forKey: .built)) ?? false
            isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
            isWishlisted = (try? c.decode(Bool.self, forKey: .isWishlisted)) ?? false
            quantity = (try? c.decode(Int.self, forKey: .quantity)) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(backupIdentifier, forKey: .backupIdentifier)
            try c.encode(checked, forKey: .checked)
            try c.encode(built, forKey: .built)
            try c.encode(isFavorite, forKey: .isFavorite)
            try c.encode(isWishlisted, forKey: .isWishlisted)
            try c.encode(quantity, forKey: .quantity)
        }
    }


    // MARK: - Data Structures

    struct BackupManifest: Codable {
        let appVersion: String
        let createdDate: Date
        let modelCount: Int
        let photoCount: Int
        let noteCount: Int
    }

    struct PhotoMetadata: Codable {
        let id: UUID
        let backupIdentifier: String  // Changed from modelId to backupIdentifier
        let timestamp: Date
        let filename: String
    }

    struct PhotoImport {
        let backupIdentifier: String
        let imageData: Data
        let timestamp: Date
    }
}

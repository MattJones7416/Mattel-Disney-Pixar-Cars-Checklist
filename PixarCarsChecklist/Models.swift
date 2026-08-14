import Foundation
import SwiftData
import CryptoKit

// MARK: - MetalModel

@Model
final class MetalModel {
    // CloudKit+SwiftData requires: either optional OR default value.
    // Give every non-optional a default.
    var id: UUID = UUID()

    var backupIdentifier: String = ""
    var checked: Bool = false
    var name: String = ""
    var number: String = ""
    var productCode: String = ""
    var character: String = ""
    var category: String = ""
    var firstReleaseYear: Int?
    var releaseCount: Int = 0
    var series: String = ""

    // Keep these optional if you like (optional doesn't need a default)
    var difficulty: Int?
    var sheets: Double?

    var link: String = ""
    var instructionsLink: String = ""
    var type: String = ""
    var status: String = ""
    var threeSixtyView: String = ""
    var modelDescription: String = ""
    var productImage: String = ""
    var releaseDate: String = ""

    var isFavorite: Bool = false
    var isWishlisted: Bool = false
    var quantity: Int = 0
    var built: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \User.models)
    var owner: User?


    init(
        id: UUID = UUID(),
        backupIdentifier: String = "",
        checked: Bool = false,
        name: String = "",
        number: String = "",
        productCode: String = "",
        character: String = "",
        category: String = "",
        firstReleaseYear: Int? = nil,
        releaseCount: Int = 0,
        series: String = "",
        difficulty: Int? = nil,
        sheets: Double? = nil,
        link: String = "",
        instructionsLink: String = "",
        type: String = "",
        status: String = "",
        threeSixtyView: String = "",
        modelDescription: String = "",
        productImage: String = "",
        releaseDate: String = "",
        isFavorite: Bool = false,
        isWishlisted: Bool = false,
        quantity: Int = 0,
        built: Bool = false,
        owner: User? = nil
    ) {
        self.id = id
        self.backupIdentifier = backupIdentifier
        self.checked = checked
        self.name = name
        self.number = number
        self.productCode = productCode
        self.character = character
        self.category = category
        self.firstReleaseYear = firstReleaseYear
        self.releaseCount = releaseCount
        self.series = series
        self.difficulty = difficulty
        self.sheets = sheets
        self.link = link
        self.instructionsLink = instructionsLink
        self.type = type
        self.status = status
        self.threeSixtyView = threeSixtyView
        self.modelDescription = modelDescription
        self.productImage = productImage
        self.releaseDate = releaseDate
        self.isFavorite = isFavorite
        self.isWishlisted = isWishlisted
        self.quantity = quantity
        self.built = built
        self.owner = owner
    }

    static func stableID(for number: String) -> UUID {
        let data = Data(number.utf8)
        let hash = SHA256.hash(data: data)
        let bytes = Array(hash)                // ← make it subscriptable
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }


    // Simple search helper used by UI
    func matches(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let q = text.lowercased()
        return name.lowercased().contains(q)
            || searchableNumbers.contains { $0.lowercased().contains(q) }
            || category.lowercased().contains(q)
            || series.lowercased().contains(q)
            || status.lowercased().contains(q)
            || type.lowercased().contains(q)
            || releaseDate.lowercased().contains(q)
    }

    var searchableNumbers: [String] {
        [number, productCode].filter { !$0.isEmpty }
    }
}

// MARK: - ModelNote

@Model
final class ModelNote {
    // All defaults to satisfy CloudKit requirements
    var id: UUID = UUID()
    var modelId: UUID = UUID()
    var text: String = ""
    var timestamp: Date = Date()

    init(
        id: UUID = UUID(),
        modelId: UUID,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.modelId = modelId
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - ModelPhoto

@Model
final class ModelPhoto {
    var id: UUID = UUID()
    var modelId: UUID = UUID()
    // Give imageData a small non-empty default so CloudKit Asset is never zero-length.
    var imageData: Data = Data([0x00])
    var timestamp: Date = Date()
    var checksum: String = ""

    init(
        id: UUID = UUID(),
        modelId: UUID,
        imageData: Data,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.modelId = modelId
        self.imageData = imageData
        self.timestamp = timestamp
        self.checksum = Self.computeChecksum(data: imageData)
    }

    static func computeChecksum(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - User

@Model
final class User {

    var id: UUID = UUID()

    // Keep OPTIONAL; no inverse here to avoid the macro cycle
    @Relationship(deleteRule: .nullify)
    var models: [MetalModel]?

    // Add a trivial initializer (satisfies the macro)
    init(id: UUID = UUID(), models: [MetalModel]? = nil) {
        self.id = id
        self.models = models
    }
}


// MARK: - AppMeta

@Model
final class AppMeta {
    var id: UUID = UUID()
    var key: String = ""
    var intValue: Int = 0

    init(id: UUID = UUID(), key: String, intValue: Int = 0) {
        self.id = id
        self.key = key
        self.intValue = intValue
    }
}

enum ModelStatus: String {
    case retired = "Retired"
    case exclusive = "Exclusive"
    case comingSoon = "Coming Soon"
    case none = ""
}

private enum ReleaseDateParserCache {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    private static let isoFormatter = ISO8601DateFormatter()
    private static var dates: [String: Date] = [:]
    private static var misses: Set<String> = []

    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cached = dates[trimmed] {
            return cached
        }
        if misses.contains(trimmed) {
            return nil
        }

        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                dates[trimmed] = date
                return date
            }
        }

        if let date = isoFormatter.date(from: trimmed) {
            dates[trimmed] = date
            return date
        }

        misses.insert(trimmed)
        return nil
    }
}

extension MetalModel {
    /// UI-agnostic representation of the status
    var statusEnum: ModelStatus {
        ModelStatus(rawValue: status) ?? .none
    }

    /// Useful small text fallback (optional)
    var statusText: String? {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var releaseDateValue: Date? {
        Self.parseReleaseDate(releaseDate)
    }

    static func parseReleaseDate(_ value: String) -> Date? {
        ReleaseDateParserCache.parse(value)
    }
}

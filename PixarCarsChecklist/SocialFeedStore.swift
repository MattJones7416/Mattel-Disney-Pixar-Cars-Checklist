import Foundation
import SwiftUI
import Security

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let socialFeedISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let socialFeedFractionalISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private func makeSocialFeedDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = socialFeedFractionalISO8601Formatter.date(from: value)
            ?? socialFeedISO8601Formatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO-8601 date: \(value)"
        )
    }
    return decoder
}

enum SocialFeedSettings {
    static let apiBaseURLKey = "socialAPIBaseURL"
    static let defaultAPIBaseURLString = "https://pixar-cars-social-api.mattjones7416.workers.dev"

    static var apiBaseURL: URL? {
        let raw = UserDefaults.standard.string(forKey: apiBaseURLKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !trimmed.isEmpty {
            return URL(string: trimmed)
        }
        return URL(string: defaultAPIBaseURLString)
    }
}

enum SocialPostKind: String, Codable, CaseIterable, Identifiable {
    case update
    case stats
    case deal
    case question

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: return "Chat"
        case .stats: return "Stats"
        case .deal: return "Deal"
        case .question: return "Question"
        }
    }

    var systemImage: String {
        switch self {
        case .update: return "bubble.left.and.bubble.right"
        case .stats: return "chart.bar.fill"
        case .deal: return "tag.fill"
        case .question: return "questionmark.circle.fill"
        }
    }
}

enum SocialAuthenticationMode: Hashable {
    case login
    case register
}

struct SocialAccountProfile: Codable, Equatable {
    var id: UUID
    var displayName: String
    var email: String
    var role: String
    var createdAt: Date
    var rulesAcceptedAt: Date?
    var collectionVisibility: String

    var hasAcceptedCommunityRules: Bool {
        rulesAcceptedAt != nil
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String,
        role: String = "user",
        createdAt: Date = Date(),
        rulesAcceptedAt: Date? = nil,
        collectionVisibility: String = "friends"
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.role = role
        self.createdAt = createdAt
        self.rulesAcceptedAt = rulesAcceptedAt
        self.collectionVisibility = collectionVisibility
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case username
        case email
        case role
        case createdAt
        case rulesAcceptedAt
        case collectionVisibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .username)
            ?? "Collector"
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "user"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        rulesAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .rulesAcceptedAt)
        collectionVisibility = try container.decodeIfPresent(String.self, forKey: .collectionVisibility) ?? "friends"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(displayName, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encode(role, forKey: .role)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(rulesAcceptedAt, forKey: .rulesAcceptedAt)
        try container.encode(collectionVisibility, forKey: .collectionVisibility)
    }
}

struct SocialStatsSnapshot: Codable, Equatable {
    var collected: Int
    var total: Int
    var built: Int
    var wishlisted: Int
    var favorites: Int

    var percentComplete: Int {
        guard total > 0 else { return 0 }
        return Int((Double(collected) / Double(total) * 100).rounded())
    }
}

struct SocialCommunityUser: Identifiable, Decodable, Equatable {
    var id: String
    var username: String
    var role: String
    var status: String
    var createdAt: String
    var collectionVisibility: String
    var collectionUpdatedAt: String?
    var collectionModelCount: Int
    var friendshipStatus: String
    var canViewCollection: Bool

    var displayName: String { username }
    var isSelf: Bool { friendshipStatus == "self" }
    var isFriend: Bool { friendshipStatus == "friends" }
    var isPendingFromThem: Bool { friendshipStatus == "pending" }
    var isRequestedByMe: Bool { friendshipStatus == "requested" }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case role
        case status
        case createdAt
        case collectionVisibility
        case collectionUpdatedAt
        case collectionModelCount
        case friendshipStatus
        case canViewCollection
    }

    init(
        id: String,
        username: String,
        role: String = "user",
        status: String = "active",
        createdAt: String = "",
        collectionVisibility: String = "friends",
        collectionUpdatedAt: String? = nil,
        collectionModelCount: Int = 0,
        friendshipStatus: String = "none",
        canViewCollection: Bool = false
    ) {
        self.id = id
        self.username = username
        self.role = role
        self.status = status
        self.createdAt = createdAt
        self.collectionVisibility = collectionVisibility
        self.collectionUpdatedAt = collectionUpdatedAt
        self.collectionModelCount = collectionModelCount
        self.friendshipStatus = friendshipStatus
        self.canViewCollection = canViewCollection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? "Collector"
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "user"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        collectionVisibility = try container.decodeIfPresent(String.self, forKey: .collectionVisibility) ?? "friends"
        collectionUpdatedAt = try container.decodeIfPresent(String.self, forKey: .collectionUpdatedAt)
        collectionModelCount = try container.decodeIfPresent(Int.self, forKey: .collectionModelCount) ?? 0
        friendshipStatus = try container.decodeIfPresent(String.self, forKey: .friendshipStatus) ?? "none"
        canViewCollection = try container.decodeIfPresent(Bool.self, forKey: .canViewCollection) ?? false
    }
}

struct SocialCollectionModelBackup: Codable, Equatable {
    var backupIdentifier: String
    var checked: Bool
    var built: Bool
    var isFavorite: Bool
    var isWishlisted: Bool
    var quantity: Int

    init(
        backupIdentifier: String,
        checked: Bool = false,
        built: Bool = false,
        isFavorite: Bool = false,
        isWishlisted: Bool = false,
        quantity: Int? = nil
    ) {
        self.backupIdentifier = backupIdentifier
        self.checked = checked
        self.built = built
        self.isFavorite = isFavorite
        self.isWishlisted = isWishlisted
        self.quantity = quantity ?? (checked ? 1 : 0)
    }

    private enum CodingKeys: String, CodingKey {
        case backupIdentifier
        case checked
        case built
        case isFavorite
        case isWishlisted
        case quantity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backupIdentifier = try container.decodeIfPresent(String.self, forKey: .backupIdentifier) ?? ""
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        built = try container.decodeIfPresent(Bool.self, forKey: .built) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isWishlisted = try container.decodeIfPresent(Bool.self, forKey: .isWishlisted) ?? false
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? (checked ? 1 : 0)
    }
}

struct SocialUserCollection: Equatable {
    var owner: SocialCommunityUser
    var models: [SocialCollectionModelBackup]
    var stats: SocialStatsSnapshot
    var updatedAt: String
    var visibility: String
}

extension SocialCollectionModelBackup {
    init(model: MetalModel) {
        self.init(
            backupIdentifier: model.backupIdentifier.isEmpty ? model.number : model.backupIdentifier,
            checked: model.checked,
            built: model.built,
            isFavorite: model.isFavorite,
            isWishlisted: model.isWishlisted,
            quantity: model.quantity
        )
    }
}

struct CatalogEditPayload: Codable, Equatable {
    var checked: Bool
    var name: String
    var number: String
    var productCode: String
    var character: String
    var firstReleaseYear: Int?
    var releaseCount: Int
    var series: String
    var difficulty: Int?
    var sheets: Double?
    var link: String
    var category: String
    var type: String
    var status: String
    var releaseDate: String
    var instructionsLink: String
    var threeSixtyView: String
    var modelDescription: String
    var productImage: String

    enum CodingKeys: String, CodingKey {
        case checked, name, number, productCode, character, firstReleaseYear, releaseCount, series
        case difficulty, sheets, link, category, type, status, releaseDate, instructionsLink
        case threeSixtyView = "360View"
        case modelDescription = "description"
        case productImage = "productimage"
    }

    init(
        checked: Bool = false,
        name: String = "",
        number: String = "",
        productCode: String = "",
        character: String = "",
        firstReleaseYear: Int? = nil,
        releaseCount: Int = 0,
        series: String = "",
        difficulty: Int? = nil,
        sheets: Double? = nil,
        link: String = "",
        category: String = "Uncategorized",
        type: String = "",
        status: String = "",
        releaseDate: String = "",
        instructionsLink: String = "",
        threeSixtyView: String = "",
        modelDescription: String = "",
        productImage: String = ""
    ) {
        self.checked = checked
        self.name = name
        self.number = number
        self.productCode = productCode
        self.character = character
        self.firstReleaseYear = firstReleaseYear
        self.releaseCount = releaseCount
        self.series = series
        self.difficulty = difficulty
        self.sheets = sheets
        self.link = link
        self.category = category
        self.type = type
        self.status = status
        self.releaseDate = releaseDate
        self.instructionsLink = instructionsLink
        self.threeSixtyView = threeSixtyView
        self.modelDescription = modelDescription
        self.productImage = productImage
    }

    init(model: MetalModel) {
        self.init(
            checked: false,
            name: model.name,
            number: model.number,
            productCode: model.productCode,
            character: model.character,
            firstReleaseYear: model.firstReleaseYear,
            releaseCount: model.releaseCount,
            series: model.series,
            difficulty: model.difficulty,
            sheets: model.sheets,
            link: model.link,
            category: model.category,
            type: model.type,
            status: model.status,
            releaseDate: model.releaseDate,
            instructionsLink: model.instructionsLink,
            threeSixtyView: model.threeSixtyView,
            modelDescription: model.modelDescription,
            productImage: model.productImage
        )
    }
}

struct SocialFeedPost: Identifiable, Codable, Equatable {
    var id: UUID
    var authorID: UUID
    var authorName: String
    var authorEmail: String
    var createdAt: Date
    var kindRawValue: String
    var message: String
    var dealURL: String
    var imageFilename: String?
    var remoteImageURLString: String?
    var stats: SocialStatsSnapshot?
    var status: String
    var reportCount: Int
    var moderationReason: String?

    var kind: SocialPostKind {
        SocialPostKind(rawValue: kindRawValue) ?? .update
    }

    var isPending: Bool {
        status == "pending"
    }

    init(
        id: UUID = UUID(),
        account: SocialAccountProfile,
        kind: SocialPostKind,
        message: String,
        dealURL: String = "",
        imageFilename: String? = nil,
        remoteImageURLString: String? = nil,
        stats: SocialStatsSnapshot? = nil,
        status: String = "approved",
        reportCount: Int = 0,
        moderationReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorID = account.id
        self.authorName = account.displayName
        self.authorEmail = account.email
        self.createdAt = createdAt
        self.kindRawValue = kind.rawValue
        self.message = message
        self.dealURL = dealURL
        self.imageFilename = imageFilename
        self.remoteImageURLString = remoteImageURLString
        self.stats = stats
        self.status = status
        self.reportCount = reportCount
        self.moderationReason = moderationReason
    }

    fileprivate init(remote: RemoteSocialPost) {
        id = UUID(uuidString: remote.id) ?? UUID()
        authorID = UUID(uuidString: remote.authorID) ?? UUID()
        authorName = remote.authorName
        authorEmail = remote.authorEmail
        createdAt = remote.createdAt
        kindRawValue = remote.kind
        message = remote.message
        dealURL = remote.dealURL
        imageFilename = nil
        remoteImageURLString = remote.imageUrl
        stats = remote.stats
        status = remote.status ?? "approved"
        reportCount = remote.reportCount
        moderationReason = remote.moderationReason
    }
}

@MainActor
final class SocialFeedStore: ObservableObject {
    @Published private(set) var account: SocialAccountProfile?
    @Published private(set) var posts: [SocialFeedPost] = []
    @Published private(set) var communityUsers: [SocialCommunityUser] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingOlderPosts = false
    @Published private(set) var hasOlderPosts = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isPosting = false
    @Published private(set) var isLoadingUsers = false
    @Published private(set) var isUpdatingFriends = false
    @Published private(set) var isSavingPrivacy = false
    @Published private(set) var isLoadingAdmin = false
    @Published private(set) var adminPosts: [SocialFeedPost] = []
    @Published private(set) var adminReports: [SocialModerationReport] = []
    @Published private(set) var adminUsers: [SocialModerationUser] = []

    private let accountURL: URL
    private let postsURL: URL
    private let imagesFolder: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let apiClient = SocialFeedAPIClient()
    private let feedPageSize = 60
    private let pendingPostRefreshGraceInterval: TimeInterval = 10 * 60
    private var authToken: String?
    private var pushTokenObserver: NSObjectProtocol?

    var isRemoteConfigured: Bool {
        SocialFeedSettings.apiBaseURL != nil
    }

    var canPost: Bool {
        account != nil
    }

    var hasAcceptedCommunityRules: Bool {
        account?.hasAcceptedCommunityRules == true
    }

    var isAdmin: Bool {
        account?.role == "admin"
    }

    init() {
        let folder = Self.socialSupportFolder()
        self.accountURL = folder.appendingPathComponent("account.json")
        self.postsURL = folder.appendingPathComponent("posts.json")
        self.imagesFolder = folder.appendingPathComponent("images", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        self.decoder = makeSocialFeedDecoder()

        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        authToken = SocialFeedTokenStore.loadToken()
        load()
        observePushTokens()

        Task {
            await refreshFeed()
            await refreshAccountIfNeeded()
            await registerStoredPushTokenIfAvailable()
        }
    }

    deinit {
        if let pushTokenObserver {
            NotificationCenter.default.removeObserver(pushTokenObserver)
        }
    }

    func refreshFeed() async {
        guard isRemoteConfigured else {
            posts.sort { $0.createdAt < $1.createdAt }
            hasOlderPosts = false
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let remotePosts = try await apiClient.fetchFeed(limit: feedPageSize, before: nil, token: authToken)
            let latestPosts = remotePosts.map(SocialFeedPost.init(remote:))
            posts = mergedLatestFeedPosts(latestPosts, receivedFullPage: remotePosts.count == feedPageSize)
            hasOlderPosts = remotePosts.count == feedPageSize
            persistPosts()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadOlderPosts() async {
        guard isRemoteConfigured else { return }
        guard !isLoadingOlderPosts, hasOlderPosts, let oldestPost = posts.first else { return }

        isLoadingOlderPosts = true
        defer { isLoadingOlderPosts = false }

        do {
            let remotePosts = try await apiClient.fetchFeed(limit: feedPageSize, before: oldestPost.createdAt, token: authToken)
            let existingIDs = Set(posts.map(\.id))
            let olderPosts = remotePosts
                .map(SocialFeedPost.init(remote:))
                .filter { !existingIDs.contains($0.id) }
            posts = (olderPosts + posts).sorted { $0.createdAt < $1.createdAt }
            hasOlderPosts = remotePosts.count == feedPageSize
            persistPosts()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func mergedLatestFeedPosts(
        _ latestPosts: [SocialFeedPost],
        receivedFullPage: Bool
    ) -> [SocialFeedPost] {
        let latestIDs = Set(latestPosts.map(\.id))
        let oldestLatestPostDate = latestPosts.map(\.createdAt).min()
        let preservedPosts = posts.filter { post in
            guard !latestIDs.contains(post.id) else { return false }
            if shouldKeepLocalPendingPost(post) { return true }
            guard receivedFullPage, let oldestLatestPostDate else { return false }
            return post.createdAt < oldestLatestPostDate
        }
        return uniqueSortedPosts(latestPosts + preservedPosts)
    }

    private func shouldKeepLocalPendingPost(_ post: SocialFeedPost) -> Bool {
        guard post.isPending, post.authorID == account?.id else { return false }
        return Date().timeIntervalSince(post.createdAt) <= pendingPostRefreshGraceInterval
    }

    private func uniqueSortedPosts(_ posts: [SocialFeedPost]) -> [SocialFeedPost] {
        var postsByID: [UUID: SocialFeedPost] = [:]
        posts.forEach { postsByID[$0.id] = $0 }
        return postsByID.values.sorted { $0.createdAt < $1.createdAt }
    }

    func authenticate(
        mode: SocialAuthenticationMode,
        username: String,
        email: String,
        password: String,
        acceptedRules: Bool = false
    ) async -> Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), password.count >= 8 else {
            lastError = "Use a valid email and a password of at least 8 characters."
            return false
        }
        if mode == .register && cleanUsername.isEmpty {
            lastError = "Choose a username."
            return false
        }
        if mode == .register && !acceptedRules {
            lastError = "Accept the community rules before creating an account."
            return false
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        guard isRemoteConfigured else {
            account = SocialAccountProfile(
                displayName: cleanUsername.isEmpty ? "Collector" : cleanUsername,
                email: cleanEmail,
                rulesAcceptedAt: acceptedRules ? Date() : nil
            )
            persistAccount()
            lastError = nil
            return true
        }

        do {
            let response: SocialAuthResponse
            switch mode {
            case .login:
                response = try await apiClient.login(email: cleanEmail, password: password)
            case .register:
                response = try await apiClient.register(
                    username: cleanUsername,
                    email: cleanEmail,
                    password: password,
                    acceptedRules: acceptedRules
                )
            }

            authToken = response.token
            SocialFeedTokenStore.saveToken(response.token)
            account = response.user.profile
            persistAccount()
            lastError = nil
            await refreshFeed()
            await refreshUsers()
            requestPushNotifications()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func signOut() {
        let tokenToRemove = SocialPushDeviceTokenStore.loadToken()
        let authTokenToUse = authToken
        if isRemoteConfigured, let authTokenToUse, let tokenToRemove {
            Task {
                try? await apiClient.unregisterDeviceToken(token: authTokenToUse, deviceToken: tokenToRemove)
            }
        }
        account = nil
        communityUsers = []
        authToken = nil
        SocialFeedTokenStore.clearToken()
        try? FileManager.default.removeItem(at: accountURL)
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard isRemoteConfigured, let authToken else {
            signOut()
            posts.removeAll()
            persistPosts()
            lastError = nil
            return true
        }

        do {
            try await apiClient.deleteAccount(token: authToken)
            signOut()
            posts.removeAll()
            persistPosts()
            lastError = nil
            await refreshFeed()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func acceptCommunityRules() async -> Bool {
        guard var currentAccount = account else {
            lastError = "Log in to accept the community rules."
            return false
        }

        if isRemoteConfigured, let authToken {
            do {
                let user = try await apiClient.acceptRules(token: authToken)
                account = user.profile
                persistAccount()
                lastError = nil
                return true
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }

        currentAccount.rulesAcceptedAt = Date()
        account = currentAccount
        persistAccount()
        lastError = nil
        return true
    }

    func refreshUsers() async {
        guard isRemoteConfigured, let authToken else {
            if account != nil {
                lastError = "Community users are temporarily unavailable."
            }
            return
        }

        isLoadingUsers = true
        defer { isLoadingUsers = false }

        do {
            communityUsers = try await apiClient.fetchUsers(token: authToken)
                .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestOrAcceptFriend(_ user: SocialCommunityUser) async {
        await updateFriendship(userID: user.id, add: true)
    }

    func removeFriend(_ user: SocialCommunityUser) async {
        await updateFriendship(userID: user.id, add: false)
    }

    private func updateFriendship(userID: String, add: Bool) async {
        guard isRemoteConfigured, let authToken else {
            lastError = "Log in to manage friends."
            return
        }

        isUpdatingFriends = true
        defer { isUpdatingFriends = false }

        do {
            let user: SocialCommunityUser
            if add {
                user = try await apiClient.requestOrAcceptFriend(token: authToken, userID: userID)
            } else {
                user = try await apiClient.removeFriend(token: authToken, userID: userID)
            }
            communityUsers.removeAll { $0.id == user.id }
            communityUsers.append(user)
            communityUsers.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func updateCollectionPrivacy(_ visibility: String) async -> Bool {
        let cleanVisibility = ["friends", "everyone", "none"].contains(visibility) ? visibility : "friends"

        guard var currentAccount = account else {
            lastError = "Log in to update collection privacy."
            return false
        }

        guard isRemoteConfigured, let authToken else {
            currentAccount.collectionVisibility = cleanVisibility
            account = currentAccount
            persistAccount()
            lastError = nil
            return true
        }

        isSavingPrivacy = true
        defer { isSavingPrivacy = false }

        do {
            let user = try await apiClient.updateCollectionPrivacy(token: authToken, visibility: cleanVisibility)
            account = user.profile
            persistAccount()
            lastError = nil
            await refreshUsers()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func publishCollectionSnapshot(models: [MetalModel]) async -> Bool {
        guard isRemoteConfigured, let authToken, account != nil else { return false }

        do {
            try await apiClient.publishCollection(
                token: authToken,
                models: models.map(SocialCollectionModelBackup.init(model:)),
                stats: Self.statsSnapshot(from: models)
            )
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func loadUserCollection(_ user: SocialCommunityUser) async -> SocialUserCollection? {
        guard isRemoteConfigured, let authToken else {
            lastError = "Log in to view collections."
            return nil
        }

        do {
            let response = try await apiClient.fetchUserCollection(token: authToken, userID: user.id)
            lastError = nil
            return SocialUserCollection(
                owner: response.user,
                models: response.collection.models,
                stats: response.collection.stats,
                updatedAt: response.collection.updatedAt,
                visibility: response.collection.visibility
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createPost(
        kind: SocialPostKind,
        message: String,
        dealURL: String,
        imageData: Data?,
        stats: SocialStatsSnapshot?
    ) async -> Bool {
        guard let account else {
            lastError = "Log in to chat."
            return false
        }
        guard account.hasAcceptedCommunityRules else {
            lastError = "Accept the community rules before posting."
            return false
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = dealURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty || imageData != nil || stats != nil || !trimmedURL.isEmpty else {
            lastError = "Add something to share."
            return false
        }
        if let filterMessage = SocialContentFilter.blockingMessage(for: "\(trimmedMessage) \(trimmedURL)") {
            lastError = filterMessage
            return false
        }

        isPosting = true
        defer { isPosting = false }

        if isRemoteConfigured, let authToken {
            do {
                let remotePost = try await apiClient.createPost(
                    token: authToken,
                    kind: kind,
                    message: trimmedMessage,
                    dealURL: kind == .deal ? trimmedURL : "",
                    imageData: imageData,
                    stats: stats
                )
                let post = SocialFeedPost(remote: remotePost)
                posts.removeAll { $0.id == post.id }
                posts.append(post)
                posts.sort { $0.createdAt < $1.createdAt }
                persistPosts()
                lastError = post.isPending ? "Message sent for moderation." : nil
                await refreshFeed()
                return true
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }

        let imageFilename = saveImageData(imageData)
        let post = SocialFeedPost(
            account: account,
            kind: kind,
            message: trimmedMessage,
            dealURL: kind == .deal ? trimmedURL : "",
            imageFilename: imageFilename,
            stats: stats
        )

        posts.append(post)
        posts.sort { $0.createdAt < $1.createdAt }
        persistPosts()
        lastError = nil
        return true
    }

    func deletePost(_ post: SocialFeedPost) async {
        if isRemoteConfigured, let authToken {
            do {
                try await apiClient.deletePost(token: authToken, postID: post.id.uuidString)
                posts.removeAll { $0.id == post.id }
                adminPosts.removeAll { $0.id == post.id }
                persistPosts()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            return
        }

        posts.removeAll { $0.id == post.id }
        if let imageFilename = post.imageFilename {
            try? FileManager.default.removeItem(at: imagesFolder.appendingPathComponent(imageFilename))
        }
        persistPosts()
    }

    func reportPost(_ post: SocialFeedPost) async {
        guard isRemoteConfigured, let authToken else {
            lastError = "Log in to report a message."
            return
        }
        do {
            try await apiClient.reportPost(token: authToken, postID: post.id.uuidString)
            lastError = "Thanks. The report has been sent."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func blockUser(_ post: SocialFeedPost) async {
        guard isRemoteConfigured, let authToken else {
            lastError = "Log in to block a user."
            return
        }
        do {
            try await apiClient.blockUser(token: authToken, userID: post.authorID.uuidString)
            posts.removeAll { $0.authorID == post.authorID }
            persistPosts()
            lastError = "User blocked."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestPushNotifications() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        MEPushNotificationCenter.requestAuthorizationAndRegister()
        if let token = SocialPushDeviceTokenStore.loadToken() {
            Task { await registerDeviceToken(token) }
        }
        #else
        lastError = "Notifications are available on iPhone and iPad."
        #endif
    }

    func loadAdminPosts(status: String) async {
        guard isRemoteConfigured, let authToken, isAdmin else { return }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            let remotePosts = try await apiClient.fetchAdminPosts(token: authToken, status: status)
            adminPosts = remotePosts
                .map(SocialFeedPost.init(remote:))
                .sorted { $0.createdAt > $1.createdAt }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadAdminReports() async {
        guard isRemoteConfigured, let authToken, isAdmin else { return }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            adminReports = try await apiClient.fetchAdminReports(token: authToken)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadAdminUsers() async {
        guard isRemoteConfigured, let authToken, isAdmin else { return }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            adminUsers = try await apiClient.fetchAdminUsers(token: authToken)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func adminUpdatePostStatus(postID: UUID, status: String, visiblePostFilter: String? = nil) async {
        guard isRemoteConfigured, let authToken, isAdmin else {
            lastError = "Admin login required."
            return
        }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            let updatedPost = try await apiClient.updateAdminPostStatus(token: authToken, postID: postID.uuidString, status: status)
            if let updatedPost {
                applyAdminPostUpdate(updatedPost, visiblePostFilter: visiblePostFilter)
            } else {
                adminPosts.removeAll { $0.id == postID }
                posts.removeAll { $0.id == postID }
                persistPosts()
            }
            if updatedPost?.status == "approved" || updatedPost?.status == "rejected" || status == "approved" || status == "rejected" {
                adminReports.removeAll { $0.postID == postID.uuidString }
            }
            if let visiblePostFilter {
                await loadAdminPosts(status: visiblePostFilter)
            }
            await loadAdminReports()
            await refreshFeed()
            if let updatedPost, updatedPost.status != status {
                lastError = "Post is still \(updatedPost.status). Pull to refresh and try again."
            } else {
                lastError = status == "approved" ? "Post approved and added to the feed." : "Post updated."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func adminDeletePost(postID: UUID) async {
        guard isRemoteConfigured, let authToken, isAdmin else {
            lastError = "Admin login required."
            return
        }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            try await apiClient.deleteAdminPost(token: authToken, postID: postID.uuidString)
            adminPosts.removeAll { $0.id == postID }
            adminReports.removeAll { $0.postID == postID.uuidString }
            await refreshFeed()
            lastError = "Post deleted."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func adminUpdateUserStatus(userID: String, status: String) async {
        guard isRemoteConfigured, let authToken, isAdmin else { return }
        do {
            if let updatedUser = try await apiClient.updateAdminUserStatus(token: authToken, userID: userID, status: status) {
                adminUsers.removeAll { $0.id == updatedUser.id }
                adminUsers.append(updatedUser)
                adminUsers.sort { $0.createdAt > $1.createdAt }
            }
            await loadAdminUsers()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyAdminPostUpdate(_ post: SocialFeedPost, visiblePostFilter: String?) {
        adminPosts.removeAll { $0.id == post.id }
        if adminPost(post, matches: visiblePostFilter) {
            adminPosts.append(post)
            adminPosts.sort { $0.createdAt > $1.createdAt }
        }
        posts.removeAll { $0.id == post.id }
        if post.status == "approved" {
            posts.append(post)
        }
        posts.sort { $0.createdAt < $1.createdAt }
        persistPosts()
    }

    private func adminPost(_ post: SocialFeedPost, matches filter: String?) -> Bool {
        switch filter {
        case "all":
            return true
        case "reported":
            return post.reportCount > 0
        case .some(let status):
            return post.status == status
        case .none:
            return false
        }
    }

    @discardableResult
    func updateCatalogModel(original: CatalogEditPayload, edited: CatalogEditPayload) async -> CatalogEditPayload? {
        guard isRemoteConfigured else {
            lastError = "Catalog service is not configured."
            return nil
        }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            let model = try await apiClient.updateCatalogModel(token: authToken, original: original, edited: edited)
            lastError = "Catalog edit saved for everyone."
            return model
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createCatalogModel(_ model: CatalogEditPayload) async -> CatalogEditPayload? {
        guard isRemoteConfigured else {
            lastError = "Catalog service is not configured."
            return nil
        }
        isLoadingAdmin = true
        defer { isLoadingAdmin = false }
        do {
            let model = try await apiClient.createCatalogModel(token: authToken, model: model)
            lastError = "Catalog model saved for everyone."
            return model
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func observePushTokens() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        pushTokenObserver = NotificationCenter.default.addObserver(
            forName: MEPushNotificationCenter.didReceiveDeviceToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.userInfo?[MEPushNotificationCenter.tokenUserInfoKey] as? String else {
                return
            }
            Task { @MainActor in
                await self?.registerDeviceToken(token)
            }
        }
        #endif
    }

    private func registerDeviceToken(_ deviceToken: String) async {
        guard isRemoteConfigured, let authToken, account != nil else { return }
        do {
            try await apiClient.registerDeviceToken(
                token: authToken,
                deviceToken: deviceToken,
                environment: SocialPushDeviceTokenStore.environment,
                platform: "ios"
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func registerStoredPushTokenIfAvailable() async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard let token = SocialPushDeviceTokenStore.loadToken() else { return }
        await registerDeviceToken(token)
        #endif
    }

    func imageURL(for post: SocialFeedPost) -> URL? {
        if let remoteImageURLString = post.remoteImageURLString,
           let url = URL(string: remoteImageURLString) {
            return url
        }
        guard let filename = post.imageFilename else { return nil }
        let url = imagesFolder.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func refreshAccountIfNeeded() async {
        guard isRemoteConfigured, let authToken else { return }
        do {
            let user = try await apiClient.me(token: authToken)
            account = user.profile
            persistAccount()
            await refreshUsers()
        } catch {
            signOut()
        }
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: accountURL.path) {
                let data = try Data(contentsOf: accountURL)
                account = try decoder.decode(SocialAccountProfile.self, from: data)
            }
            if FileManager.default.fileExists(atPath: postsURL.path) {
                let data = try Data(contentsOf: postsURL)
                posts = try decoder.decode([SocialFeedPost].self, from: data)
                    .sorted { $0.createdAt < $1.createdAt }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistAccount() {
        do {
            guard let account else { return }
            let data = try encoder.encode(account)
            try data.write(to: accountURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistPosts() {
        do {
            let data = try encoder.encode(posts)
            try data.write(to: postsURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func saveImageData(_ imageData: Data?) -> String? {
        guard let imageData else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = imagesFolder.appendingPathComponent(filename)
        let output = socialFeedCompressedImageData(imageData) ?? imageData

        do {
            try output.write(to: url, options: .atomic)
            return filename
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private static func socialSupportFolder() -> URL {
        let root: URL
        do {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            root = FileManager.default.temporaryDirectory
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "PixarCarsChecklist"
        let folder = root
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("SocialFeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func statsSnapshot(from models: [MetalModel]) -> SocialStatsSnapshot {
        SocialStatsSnapshot(
            collected: models.filter { $0.checked }.count,
            total: models.count,
            built: models.filter { $0.built }.count,
            wishlisted: models.filter { $0.isWishlisted }.count,
            favorites: models.filter { $0.isFavorite }.count
        )
    }
}

private struct SocialAuthResponse: Decodable {
    let token: String
    let user: RemoteSocialUser
}

private struct RemoteSocialUser: Decodable {
    let id: String
    let username: String
    let email: String
    let role: String
    let status: String
    let createdAt: Date
    let rulesAcceptedAt: Date?
    let collectionVisibility: String?

    var profile: SocialAccountProfile {
        SocialAccountProfile(
            id: UUID(uuidString: id) ?? UUID(),
            displayName: username,
            email: email,
            role: role,
            createdAt: createdAt,
            rulesAcceptedAt: rulesAcceptedAt,
            collectionVisibility: collectionVisibility ?? "friends"
        )
    }
}

private struct RemoteSocialPost: Decodable {
    let id: String
    let authorID: String
    let authorName: String
    let authorEmail: String
    let kind: String
    let message: String
    let dealURL: String
    let imageUrl: String?
    let stats: SocialStatsSnapshot?
    let reportCount: Int
    let status: String?
    let moderationReason: String?
    let createdAt: Date
}

private struct RemoteFeedResponse: Decodable {
    let posts: [RemoteSocialPost]
}

private struct RemoteCreatePostResponse: Decodable {
    let post: RemoteSocialPost
}

private struct RemoteMeResponse: Decodable {
    let user: RemoteSocialUser
}

private struct RemoteCommunityUsersResponse: Decodable {
    let users: [SocialCommunityUser]
}

private struct RemoteFriendshipResponse: Decodable {
    let user: SocialCommunityUser
}

private struct RemotePublishCollectionResponse: Decodable {
    let ok: Bool
    let updatedAt: String?
}

struct RemoteUserCollectionResponse: Decodable {
    let user: SocialCommunityUser
    let collection: RemoteCollectionSnapshot
}

struct RemoteCollectionSnapshot: Decodable {
    let models: [SocialCollectionModelBackup]
    let stats: SocialStatsSnapshot
    let updatedAt: String
    let visibility: String

    private enum CodingKeys: String, CodingKey {
        case models
        case stats
        case updatedAt
        case visibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([SocialCollectionModelBackup].self, forKey: .models) ?? []
        stats = try container.decodeIfPresent(SocialStatsSnapshot.self, forKey: .stats) ?? SocialStatsSnapshot(
            collected: models.filter { $0.checked }.count,
            total: models.count,
            built: models.filter { $0.built }.count,
            wishlisted: models.filter { $0.isWishlisted }.count,
            favorites: models.filter { $0.isFavorite }.count
        )
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "friends"
    }
}

struct SocialModerationReport: Identifiable, Decodable, Equatable {
    let id: String
    let postID: String
    let reason: String
    let createdAt: Date
    let reporterID: String
    let reporterName: String
    let reporterEmail: String
    let authorID: String
    let authorName: String
    let authorEmail: String
    let kind: String
    let message: String
    let dealURL: String
    let imageUrl: String?
    let stats: SocialStatsSnapshot?
    let status: String
    let moderationReason: String
    let reportCount: Int
    let postCreatedAt: Date
}

struct SocialModerationUser: Identifiable, Decodable, Equatable {
    let id: String
    let username: String
    let email: String
    let role: String
    let status: String
    let createdAt: Date
    let rulesAcceptedAt: Date?
}

private struct RemoteAdminPostsResponse: Decodable {
    let posts: [RemoteSocialPost]
}

private struct RemoteAdminReportsResponse: Decodable {
    let reports: [SocialModerationReport]
}

private struct RemoteAdminUsersResponse: Decodable {
    let users: [SocialModerationUser]
}

private struct RemoteAdminPostUpdateResponse: Decodable {
    let ok: Bool
    let post: RemoteSocialPost?
}

private struct RemoteAdminUserUpdateResponse: Decodable {
    let ok: Bool
    let user: SocialModerationUser?
}

private struct RemoteCatalogUpdateResponse: Decodable {
    let ok: Bool
    let commit: String?
    let model: CatalogEditPayload
}

private final class SocialFeedAPIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        self.decoder = makeSocialFeedDecoder()
    }

    func fetchFeed(limit: Int, before: Date?, token: String?) async throws -> [RemoteSocialPost] {
        var components = URLComponents(url: try endpoint("v1/feed"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: socialFeedFractionalISO8601Formatter.string(from: before)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw SocialFeedAPIError.missingBaseURL }
        let response: RemoteFeedResponse = try await request(url: url, token: token)
        return response.posts
    }

    func register(username: String, email: String, password: String, acceptedRules: Bool) async throws -> SocialAuthResponse {
        try await request(
            path: "v1/auth/register",
            method: "POST",
            jsonObject: [
                "username": username,
                "email": email,
                "password": password,
                "acceptedRules": acceptedRules
            ]
        )
    }

    func login(email: String, password: String) async throws -> SocialAuthResponse {
        try await request(
            path: "v1/auth/login",
            method: "POST",
            body: [
                "email": email,
                "password": password
            ]
        )
    }

    func me(token: String) async throws -> RemoteSocialUser {
        let response: RemoteMeResponse = try await request(path: "v1/me", token: token)
        return response.user
    }

    func deleteAccount(token: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/me",
            method: "DELETE",
            token: token
        )
    }

    func acceptRules(token: String) async throws -> RemoteSocialUser {
        let response: RemoteMeResponse = try await request(
            path: "v1/me/accept-rules",
            method: "POST",
            token: token,
            jsonObject: [:] as [String: String]
        )
        return response.user
    }

    func fetchUsers(token: String) async throws -> [SocialCommunityUser] {
        let response: RemoteCommunityUsersResponse = try await request(path: "v1/users", token: token)
        return response.users
    }

    func requestOrAcceptFriend(token: String, userID: String) async throws -> SocialCommunityUser {
        let response: RemoteFriendshipResponse = try await request(
            path: "v1/users/\(userID)/friend",
            method: "POST",
            token: token,
            jsonObject: [:] as [String: String]
        )
        return response.user
    }

    func removeFriend(token: String, userID: String) async throws -> SocialCommunityUser {
        let response: RemoteFriendshipResponse = try await request(
            path: "v1/users/\(userID)/friend",
            method: "DELETE",
            token: token,
            jsonObject: [:] as [String: String]
        )
        return response.user
    }

    func updateCollectionPrivacy(token: String, visibility: String) async throws -> RemoteSocialUser {
        let response: RemoteMeResponse = try await request(
            path: "v1/me/privacy",
            method: "PATCH",
            token: token,
            body: ["collectionVisibility": visibility]
        )
        return response.user
    }

    func publishCollection(token: String, models: [SocialCollectionModelBackup], stats: SocialStatsSnapshot) async throws {
        let _: RemotePublishCollectionResponse = try await request(
            path: "v1/me/collection",
            method: "PUT",
            token: token,
            jsonObject: [
                "models": try jsonArray(models),
                "stats": try jsonDictionary(stats)
            ]
        )
    }

    func fetchUserCollection(token: String, userID: String) async throws -> RemoteUserCollectionResponse {
        try await request(path: "v1/users/\(userID)/collection", token: token)
    }

    func createPost(
        token: String,
        kind: SocialPostKind,
        message: String,
        dealURL: String,
        imageData: Data?,
        stats: SocialStatsSnapshot?
    ) async throws -> RemoteSocialPost {
        var body: [String: Any] = [
            "kind": kind.rawValue,
            "message": message,
            "dealURL": dealURL
        ]
        if let stats {
            body["stats"] = [
                "collected": stats.collected,
                "total": stats.total,
                "built": stats.built,
                "wishlisted": stats.wishlisted,
                "favorites": stats.favorites
            ]
        }
        if let imageData {
            let compressed = socialFeedCompressedImageData(imageData, maxDimension: 1200, targetBytes: 850_000) ?? imageData
            body["imageBase64"] = "data:image/jpeg;base64,\(compressed.base64EncodedString())"
        }

        let response: RemoteCreatePostResponse = try await request(
            path: "v1/posts",
            method: "POST",
            token: token,
            jsonObject: body
        )
        return response.post
    }

    func reportPost(token: String, postID: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/posts/\(postID)/report",
            method: "POST",
            token: token,
            body: ["reason": "Reported from app"]
        )
    }

    func deletePost(token: String, postID: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/posts/\(postID)",
            method: "DELETE",
            token: token
        )
    }

    func blockUser(token: String, userID: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/users/\(userID)/block",
            method: "POST",
            token: token,
            jsonObject: [:] as [String: String]
        )
    }

    func registerDeviceToken(token: String, deviceToken: String, environment: String, platform: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/push/register",
            method: "POST",
            token: token,
            body: [
                "token": deviceToken,
                "environment": environment,
                "platform": platform
            ]
        )
    }

    func unregisterDeviceToken(token: String, deviceToken: String) async throws {
        let cleanToken = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let _: EmptyResponse = try await request(
            path: "v1/push/tokens/\(cleanToken)",
            method: "DELETE",
            token: token
        )
    }

    func fetchAdminPosts(token: String, status: String) async throws -> [RemoteSocialPost] {
        var components = URLComponents(url: try endpoint("v1/admin/posts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "status", value: status)]
        guard let url = components?.url else { throw SocialFeedAPIError.missingBaseURL }
        let response: RemoteAdminPostsResponse = try await request(url: url, token: token)
        return response.posts
    }

    func fetchAdminReports(token: String) async throws -> [SocialModerationReport] {
        let response: RemoteAdminReportsResponse = try await request(path: "v1/admin/reports", token: token)
        return response.reports
    }

    func fetchAdminUsers(token: String) async throws -> [SocialModerationUser] {
        let response: RemoteAdminUsersResponse = try await request(path: "v1/admin/users", token: token)
        return response.users
    }

    func updateAdminPostStatus(token: String, postID: String, status: String) async throws -> SocialFeedPost? {
        let response: RemoteAdminPostUpdateResponse = try await request(
            path: "v1/admin/posts/\(postID)",
            method: "PATCH",
            token: token,
            body: ["status": status]
        )
        return response.post.map(SocialFeedPost.init(remote:))
    }

    func deleteAdminPost(token: String, postID: String) async throws {
        let _: EmptyResponse = try await request(
            path: "v1/admin/posts/\(postID)",
            method: "DELETE",
            token: token
        )
    }

    func updateAdminUserStatus(token: String, userID: String, status: String) async throws -> SocialModerationUser? {
        let response: RemoteAdminUserUpdateResponse = try await request(
            path: "v1/admin/users/\(userID)",
            method: "PATCH",
            token: token,
            body: ["status": status]
        )
        return response.user
    }

    func updateCatalogModel(token: String?, original: CatalogEditPayload, edited: CatalogEditPayload) async throws -> CatalogEditPayload {
        let response: RemoteCatalogUpdateResponse = try await request(
            path: "v1/catalog/models",
            method: "POST",
            token: token,
            jsonObject: [
                "originalNumber": original.number,
                "originalModel": try jsonDictionary(original),
                "model": try jsonDictionary(edited)
            ]
        )
        return response.model
    }

    func createCatalogModel(token: String?, model: CatalogEditPayload) async throws -> CatalogEditPayload {
        let response: RemoteCatalogUpdateResponse = try await request(
            path: "v1/catalog/models",
            method: "POST",
            token: token,
            jsonObject: [
                "create": true,
                "model": try jsonDictionary(model)
            ]
        )
        return response.model
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: [String: String]? = nil
    ) async throws -> T {
        let jsonObject = body.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key, $0.value) }) }
        return try await request(path: path, method: method, token: token, jsonObject: jsonObject)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        token: String? = nil,
        jsonObject: Any? = nil
    ) async throws -> T {
        try await request(url: endpoint(path), method: method, token: token, jsonObject: jsonObject)
    }

    private func request<T: Decodable>(
        url: URL,
        method: String = "GET",
        token: String? = nil,
        jsonObject: Any? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonObject {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SocialFeedAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = try? decoder.decode(RemoteErrorResponse.self, from: data) {
                throw SocialFeedAPIError.server(error.error)
            }
            throw SocialFeedAPIError.server("Request failed (\(httpResponse.statusCode)).")
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try decoder.decode(T.self, from: data)
    }

    private func endpoint(_ path: String) throws -> URL {
        guard var url = SocialFeedSettings.apiBaseURL else { throw SocialFeedAPIError.missingBaseURL }
        path.split(separator: "/").forEach { component in
            url.appendPathComponent(String(component))
        }
        return url
    }

    private func jsonDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] ?? [:]
    }

    private func jsonArray<T: Encodable>(_ value: [T]) throws -> [Any] {
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data, options: [])) as? [Any] ?? []
    }
}

private struct EmptyResponse: Decodable {}

private struct RemoteErrorResponse: Decodable {
    let error: String
}

private enum SocialFeedAPIError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Community is temporarily unavailable."
        case .invalidResponse:
            return "The community server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

private enum SocialContentFilter {
    private static let blockedTerms: [String] = [
        "abuse",
        "bully",
        "harass",
        "hate crime",
        "kill yourself",
        "kys",
        "nazi",
        "kkk",
        "retard",
        "nonce",
        "paedo",
        "pedo",
        "porn",
        "sex",
        "nude",
        "nudes",
        "onlyfans",
        "fuck",
        "fucker",
        "shit",
        "cunt",
        "bitch",
        "bastard",
        "dick",
        "scam",
        "scammer",
        "crypto giveaway",
        "telegram",
        "whatsapp me",
        "buy followers"
    ]

    static func blockingMessage(for text: String) -> String? {
        let normalized = normalize(text)
        let matched = blockedTerms.contains { term in
            normalized.contains(" \(normalize(term).trimmingCharacters(in: .whitespacesAndNewlines)) ")
        }
        return matched ? "That message is blocked by the community filter." : nil
    }

    private static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let collapsed = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )
        return " \(collapsed.split(separator: " ").joined(separator: " ")) "
    }
}

private enum SocialFeedTokenStore {
    private static let service = "PixarCarsChecklist.SocialFeed"
    private static let account = "authToken"

    static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        clearToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum SocialPushDeviceTokenStore {
    private static let key = "socialPushDeviceToken"

    static var environment: String {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return MEPushNotificationCenter.environment
        #else
        return "production"
        #endif
    }

    static func loadToken() -> String? {
        let token = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }
}

private func socialFeedCompressedImageData(
    _ data: Data,
    maxDimension: CGFloat = 1600,
    targetBytes: Int = 900_000
) -> Data? {
    #if canImport(UIKit)
    guard let image = UIImage(data: data) else { return nil }
    let longEdge = max(image.size.width, image.size.height)
    let scale = min(1, maxDimension / max(1, longEdge))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }

    for quality in stride(from: 0.82, through: 0.42, by: -0.1) {
        if let output = scaled.jpegData(compressionQuality: quality), output.count <= targetBytes {
            return output
        }
    }
    return scaled.jpegData(compressionQuality: 0.38)
    #elseif canImport(AppKit)
    guard let image = NSImage(data: data),
          let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? data) else { return nil }
    let longEdge = max(CGFloat(rep.pixelsWide), CGFloat(rep.pixelsHigh))
    let scale = min(1, maxDimension / max(1, longEdge))
    let size = NSSize(width: CGFloat(rep.pixelsWide) * scale, height: CGFloat(rep.pixelsHigh) * scale)

    let scaled = NSImage(size: size)
    scaled.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: size))
    scaled.unlockFocus()

    for quality in stride(from: 0.82, through: 0.42, by: -0.1) {
        if let tiff = scaled.tiffRepresentation,
           let output = NSBitmapImageRep(data: tiff)?.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
           ),
           output.count <= targetBytes {
            return output
        }
    }
    if let tiff = scaled.tiffRepresentation {
        return NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.38])
    }
    return nil
    #else
    return nil
    #endif
}

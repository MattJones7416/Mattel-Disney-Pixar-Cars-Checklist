import SwiftUI
import SDWebImageSwiftUI

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SocialFeedView: View {
    @ObservedObject var dataManager: DataManager
    @ObservedObject var store: SocialFeedStore
    var onViewCollection: (SocialCommunityUser) -> Void = { _ in }
    var onPublishCollection: () -> Void = {}

    @State private var showingAuthSheet = false
    @State private var authMode: SocialAuthenticationMode = .login
    @State private var showingUsersSheet = false

    private let accentColor = Color(hex: "66D12D")
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            SocialFeedHeader(
                store: store,
                accentColor: accentColor,
                onLogin: {
                    authMode = .login
                    showingAuthSheet = true
                },
                onUsers: {
                    openCommunityUsers()
                }
            )

            Divider()

            SocialChatTimeline(store: store, accentColor: accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            if store.canPost {
                SocialChatComposer(
                    dataManager: dataManager,
                    store: store,
                    accentColor: accentColor
                )
            } else {
                SocialLoggedOutComposer(accentColor: accentColor) {
                    authMode = .login
                    showingAuthSheet = true
                }
            }
        }
        .background(platformPageBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.refreshFeed()
        }
        .onReceive(refreshTimer) { _ in
            Task { await store.refreshFeed() }
        }
        .onChange(of: store.account?.id) { _, newValue in
            guard newValue != nil else { return }
            onPublishCollection()
            Task { await store.refreshUsers() }
        }
        .sheet(isPresented: $showingAuthSheet) {
            SocialAuthSheet(
                store: store,
                mode: $authMode,
                accentColor: accentColor
            )
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 430)
            #endif
        }
        .sheet(isPresented: $showingUsersSheet) {
            CommunityUsersSheet(
                store: store,
                accentColor: accentColor,
                onViewCollection: onViewCollection
            )
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
    }

    private func openCommunityUsers() {
        guard store.account != nil else {
            authMode = .login
            showingAuthSheet = true
            return
        }
        showingUsersSheet = true
        onPublishCollection()
        Task { await store.refreshUsers() }
    }
}

private struct SocialFeedHeader: View {
    @ObservedObject var store: SocialFeedStore
    let accentColor: Color
    let onLogin: () -> Void
    let onUsers: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Community")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onUsers) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(store.account == nil ? .secondary : accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.gray.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Friends and collections")

            if let account = store.account {
                Menu {
                    Button(role: .destructive) {
                        store.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Text(initials(for: account.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account")
            } else {
                Button(action: onLogin) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.gray.opacity(0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log in")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(platformPanelBackground)
    }

    private var statusText: String {
        if let account = store.account {
            return account.displayName
        }
        return "Read only"
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "ME" : text
    }
}

private struct CommunityUsersSheet: View {
    @ObservedObject var store: SocialFeedStore
    let accentColor: Color
    let onViewCollection: (SocialCommunityUser) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error = store.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(error.lowercased().contains("sent") || error.lowercased().contains("updated") ? .secondary : .red)
                    }
                }

                if store.communityUsers.isEmpty && !store.isLoadingUsers {
                    Section {
                        Text("No collectors found yet.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Collectors") {
                        ForEach(store.communityUsers) { user in
                            CommunityUserRow(
                                user: user,
                                accentColor: accentColor,
                                isUpdating: store.isUpdatingFriends,
                                onView: {
                                    dismiss()
                                    onViewCollection(user)
                                },
                                onAddOrAccept: {
                                    Task { await store.requestOrAcceptFriend(user) }
                                },
                                onRemove: {
                                    Task { await store.removeFriend(user) }
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Collectors")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await store.refreshUsers() }
                    } label: {
                        if store.isLoadingUsers {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isLoadingUsers)
                }
            }
            .task {
                await store.refreshUsers()
            }
        }
    }
}

private struct CommunityUserRow: View {
    let user: SocialCommunityUser
    let accentColor: Color
    let isUpdating: Bool
    let onView: () -> Void
    let onAddOrAccept: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accentColor.opacity(user.isFriend || user.isSelf ? 0.22 : 0.12))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(initials(for: user.displayName))
                            .font(.caption.weight(.bold))
                            .foregroundColor(user.isFriend || user.isSelf ? accentColor : .secondary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                if user.canViewCollection {
                    Button(action: onView) {
                        Label("View", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                }

                if !user.isSelf {
                    Button(role: user.isFriend || user.isRequestedByMe ? .destructive : nil) {
                        if user.isFriend || user.isRequestedByMe {
                            onRemove()
                        } else {
                            onAddOrAccept()
                        }
                    } label: {
                        Label(friendActionTitle, systemImage: friendActionImage)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdating)
                }

                Spacer()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private var statusText: String {
        if user.isSelf {
            return "Your collection is \(privacyLabel(user.collectionVisibility))"
        }
        if user.isFriend {
            return "Friends"
        }
        if user.isPendingFromThem {
            return "Friend request from them"
        }
        if user.isRequestedByMe {
            return "Friend request sent"
        }
        if user.collectionVisibility == "everyone" {
            return "Collection visible to everyone"
        }
        if user.collectionVisibility == "none" {
            return "Collection private"
        }
        return "Friends-only collection"
    }

    private var friendActionTitle: String {
        if user.isFriend { return "Remove" }
        if user.isPendingFromThem { return "Confirm" }
        if user.isRequestedByMe { return "Cancel" }
        return "Add"
    }

    private var friendActionImage: String {
        if user.isFriend { return "person.badge.minus" }
        if user.isPendingFromThem { return "checkmark.circle" }
        if user.isRequestedByMe { return "xmark.circle" }
        return "person.badge.plus"
    }

    private func privacyLabel(_ value: String) -> String {
        switch value {
        case "everyone": return "visible to everyone"
        case "none": return "private"
        default: return "friends only"
        }
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "ME" : text
    }
}

private struct SocialChatTimeline: View {
    @ObservedObject var store: SocialFeedStore
    let accentColor: Color
    @State private var newestPostID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.posts.isEmpty {
                        SocialEmptyFeedView()
                            .padding(.top, 28)
                    } else {
                        if store.hasOlderPosts {
                            Button {
                                loadOlder(using: proxy)
                            } label: {
                                if store.isLoadingOlderPosts {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Load Older", systemImage: "chevron.up")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isLoadingOlderPosts)
                            .padding(.bottom, 4)
                        }

                        ForEach(store.posts) { post in
                            SocialMessageBubble(
                                post: post,
                                imageURL: store.imageURL(for: post),
                                isMine: store.account?.id == post.authorID,
                                accentColor: accentColor,
                                canDelete: store.account?.id == post.authorID,
                                canReport: store.isRemoteConfigured,
                                canBlock: store.isRemoteConfigured && store.account?.id != post.authorID,
                                onDelete: { Task { await store.deletePost(post) } },
                                onReport: {
                                    Task { await store.reportPost(post) }
                                },
                                onBlock: {
                                    Task { await store.blockUser(post) }
                                }
                            )
                            .id(post.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .onAppear {
                newestPostID = store.posts.last?.id
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: store.posts.last?.id) { _, newValue in
                newestPostID = newValue
                scrollToBottom(proxy, animated: true)
            }
        }
    }

    private func loadOlder(using proxy: ScrollViewProxy) {
        let anchor = store.posts.first?.id
        Task {
            await store.loadOlderPosts()
            guard let anchor else { return }
            await MainActor.run {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = store.posts.last else { return }
        let action = {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                action()
            }
        } else {
            action()
        }
    }
}

private struct SocialMessageBubble: View {
    let post: SocialFeedPost
    let imageURL: URL?
    let isMine: Bool
    let accentColor: Color
    let canDelete: Bool
    let canReport: Bool
    let canBlock: Bool
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    @State private var showingBlockConfirmation = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 48)
            } else {
                avatar
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !isMine {
                        Text(post.authorName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    if post.isPending {
                        Text("Pending")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !post.message.isEmpty {
                        Text(post.message)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let stats = post.stats {
                        SocialStatsStrip(stats: stats, accentColor: accentColor)
                    }

                    if let imageURL, !post.isPending {
                        SocialFeedImage(url: imageURL)
                    } else if post.remoteImageURLString != nil && post.isPending {
                        SocialPendingPhotoView()
                    }

                    if let dealURL = URL(string: post.dealURL), !post.dealURL.isEmpty {
                        Link(destination: dealURL) {
                            Label("Open deal", systemImage: "tag.fill")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isMine ? accentColor.opacity(0.22) : platformPanelBackground)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isMine ? accentColor.opacity(0.18) : Color.gray.opacity(0.12), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Text(post.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Menu {
                        if canDelete {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if canReport {
                            Button(action: onReport) {
                                Label("Report", systemImage: "flag")
                            }
                        }
                        if canBlock {
                            Button(role: .destructive) {
                                showingBlockConfirmation = true
                            } label: {
                                Label("Block User", systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Block \(post.authorName)?", isPresented: $showingBlockConfirmation) {
                        Button("Block User", role: .destructive, action: onBlock)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Their posts will be hidden from your chat feed.")
                    }
                }
            }
            .frame(maxWidth: 560, alignment: isMine ? .trailing : .leading)

            if isMine {
                avatar
            } else {
                Spacer(minLength: 48)
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(isMine ? accentColor.opacity(0.24) : Color.gray.opacity(0.16))
            .frame(width: 28, height: 28)
            .overlay(
                Text(initials(for: post.authorName))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(isMine ? accentColor : .secondary)
            )
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(parts).uppercased()
        return text.isEmpty ? "ME" : text
    }
}

private struct SocialPendingPhotoView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .semibold))
            Text("Photo awaiting approval")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SocialChatComposer: View {
    @ObservedObject var dataManager: DataManager
    @ObservedObject var store: SocialFeedStore
    let accentColor: Color

    @State private var composerText = ""
    @State private var dealURL = ""
    @State private var selectedKind: SocialPostKind = .update
    @State private var includeStats = false
    @State private var selectedImageData: Data?
    @State private var selectedImagePreview: MEPlatformImage?
    @State private var showingRulesSheet = false

    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    private var statsSnapshot: SocialStatsSnapshot {
        SocialStatsSnapshot(
            collected: dataManager.allModels.filter { $0.checked }.count,
            total: dataManager.allModels.count,
            built: dataManager.allModels.filter { $0.built }.count,
            wishlisted: dataManager.allModels.filter { $0.isWishlisted }.count,
            favorites: dataManager.allModels.filter { $0.isFavorite }.count
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(error.lowercased().contains("sent") || error.lowercased().contains("thanks") ? .secondary : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedKind == .deal {
                TextField("Deal link", text: $dealURL)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            if includeStats {
                SocialStatsStrip(stats: statsSnapshot, accentColor: accentColor)
            }

            if let previewImage = selectedImagePreview {
                ZStack(alignment: .topTrailing) {
                    socialImageView(previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        selectedImageData = nil
                        selectedImagePreview = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    ForEach(SocialPostKind.allCases) { kind in
                        Button {
                            selectedKind = kind
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: selectedKind.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                TextField("Message", text: $composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(platformSecondaryPanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    includeStats.toggle()
                    if includeStats {
                        selectedKind = .stats
                    }
                } label: {
                    Image(systemName: includeStats ? "chart.bar.fill" : "chart.bar")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(includeStats ? accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                        .foregroundColor(includeStats ? accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(includeStats ? "Remove stats" : "Add stats")

                #if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add image")
                #endif

                Button {
                    guard store.hasAcceptedCommunityRules else {
                        showingRulesSheet = true
                        return
                    }
                    Task {
                        let sent = await store.createPost(
                            kind: selectedKind,
                            message: composerText,
                            dealURL: selectedKind == .deal ? dealURL : "",
                            imageData: selectedImageData,
                            stats: includeStats ? statsSnapshot : nil
                        )
                        if sent {
                            composerText = ""
                            dealURL = ""
                            includeStats = false
                            selectedKind = .update
                            selectedImageData = nil
                            selectedImagePreview = nil
                        }
                    }
                } label: {
                    if store.isPosting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(accentColor)
                            .frame(width: 36, height: 36)
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.isPosting)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(platformPanelBackground)
        .sheet(isPresented: $showingRulesSheet) {
            SocialCommunityRulesSheet(store: store, accentColor: accentColor)
        }
        #if canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    selectedImagePreview = socialImageFromData(data)
                }
                selectedPhotoItem = nil
            }
        }
        #endif
    }
}

private struct SocialLoggedOutComposer: View {
    let accentColor: Color
    let onLogin: () -> Void

    var body: some View {
        Button(action: onLogin) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Log in to chat")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(platformPanelBackground)
    }
}

private struct SocialCommunityRulesSection: View {
    var body: some View {
        Section("Community Guidelines") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Do not post abuse, harassment, hate, sexual content, illegal content, spam, scams, copyrighted images, personal information, threats, or bullying.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Posts can be reported, removed, or held for moderation. Photo posts require admin approval before appearing in the public feed.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Link("Contact Support", destination: socialSupportMailURL)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SocialCommunityRulesSheet: View {
    @ObservedObject var store: SocialFeedStore
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SocialCommunityRulesSection()

                if let error = store.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Community Rules")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await store.acceptCommunityRules() {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Accept")
                            .foregroundColor(accentColor)
                    }
                }
            }
        }
    }
}

private struct SocialAuthSheet: View {
    @ObservedObject var store: SocialFeedStore
    @Binding var mode: SocialAuthenticationMode
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedRules = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Log In").tag(SocialAuthenticationMode.login)
                        Text("Create").tag(SocialAuthenticationMode.register)
                    }
                    .pickerStyle(.segmented)

                    if mode == .register {
                        TextField("Username", text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                    }

                    TextField("Email", text: $email)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)

                }

                if mode == .register {
                    SocialCommunityRulesSection()

                    Section {
                        Toggle("I accept the community rules", isOn: $acceptedRules)
                    }
                }

                if let error = store.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(mode == .login ? "Log In" : "Create Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let success = await store.authenticate(
                                mode: mode,
                                username: username,
                                email: email,
                                password: password,
                                acceptedRules: acceptedRules
                            )
                            if success {
                                dismiss()
                            }
                        }
                    } label: {
                        if store.isAuthenticating {
                            ProgressView()
                        } else {
                            Text(mode == .login ? "Log In" : "Create")
                                .foregroundColor(accentColor)
                        }
                    }
                    .disabled(store.isAuthenticating || (mode == .register && !acceptedRules))
                }
            }
        }
    }
}

private struct SocialStatsStrip: View {
    let stats: SocialStatsSnapshot
    let accentColor: Color

    var body: some View {
        HStack(spacing: 6) {
            SocialStatPill(value: "\(stats.percentComplete)%", label: "Done", color: accentColor)
            SocialStatPill(value: "\(stats.collected)", label: "Owned", color: .blue)
            SocialStatPill(value: "\(stats.built)", label: "Unboxed", color: .orange)
            SocialStatPill(value: "\(stats.wishlisted)", label: "Wish", color: .pink)
        }
    }
}

private struct SocialStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SocialFeedImage: View {
    let url: URL

    var body: some View {
        Group {
            if url.isFileURL, let image = socialImageFromFile(url) {
                socialImageView(image)
                    .resizable()
                    .scaledToFill()
            } else {
                WebImage(url: url, options: [.scaleDownLargeImages]) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SocialEmptyFeedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)
            Text("No messages yet")
                .font(.headline)
            Text("The first community messages will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(platformPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private var platformPageBackground: Color {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return Color(.systemGroupedBackground)
    #else
    return Color(NSColor.windowBackgroundColor)
    #endif
}

private var platformPanelBackground: Color {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return Color(.secondarySystemGroupedBackground)
    #else
    return Color(NSColor.underPageBackgroundColor)
    #endif
}

private var platformSecondaryPanelBackground: Color {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return Color(.systemBackground)
    #else
    return Color(NSColor.textBackgroundColor)
    #endif
}

private let socialSupportMailURL = URL(string: "mailto:info@stonebrookstudios.co.uk")!

private func socialImageFromData(_ data: Data) -> MEPlatformImage? {
    #if os(iOS)
    return UIImage(data: data)
    #else
    return NSImage(data: data)
    #endif
}

private func socialImageFromFile(_ url: URL) -> MEPlatformImage? {
    #if os(iOS)
    return UIImage(contentsOfFile: url.path)
    #else
    return NSImage(contentsOf: url)
    #endif
}

private func socialImageView(_ image: MEPlatformImage) -> Image {
    #if os(iOS)
    return Image(uiImage: image)
    #else
    return Image(nsImage: image)
    #endif
}

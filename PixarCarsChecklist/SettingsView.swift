import SwiftUI
import UniformTypeIdentifiers
import SDWebImageSwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject var socialFeedStore: SocialFeedStore
    var viewedCollection: ViewedCollectionState?
    var onCloseViewedCollection: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var backupManager: BackupManager
    @EnvironmentObject var purchaseManager: PurchaseManager

    @AppStorage("devModeEnabled") private var devModeEnabled: Bool = false
    @AppStorage("devCatalogURL") private var devCatalogURL: String = ""

    @State private var showingBackupAlert = false
    @State private var showingRestorePicker = false
    @State private var backupFile: IdentifiableURL?
    @State private var restoreFile: URL?
    @State private var isProcessing = false
    @State private var operationStatus: (isSuccess: Bool, message: String)?
    @State private var showingResetConfirmation = false
    @State private var isRefreshingCatalog = false
    @State private var showingAdminLogin = false
    @State private var showingAdminModeration = false
    @State private var showingAddCatalogModel = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingUnlockSheet = false

    private let paypalURL = URL(string: "https://www.paypal.com/paypalme/drummermattdesigns")!
    private let supportMailURL = URL(string: "mailto:info@stonebrookstudios.co.uk")!
    private let privacyPolicyURL = URL(string: "https://pixar-cars-social-api.mattjones7416.workers.dev/privacy")!
    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                dataManagementSection
                developerSection
                communitySection
                supportSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .modifier(MacFormStyling())

        // File importer
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                restoreFile = urls.first
            case .failure(let error):
                operationStatus = (false, "Import failed: \(error.localizedDescription)")
            }
        }

        // Create backup alert
        .alert("Create Backup?", isPresented: $showingBackupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Create") { createBackup() }
        }

        // Restore backup alert (presented when restoreFile is set)
        .alert(
            "Restore Backup?",
            isPresented: Binding(
                get: { restoreFile != nil },
                set: { if !$0 { restoreFile = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { restoreBackup() }
        } message: {
            Text("""
                 This will restore your collection status, wishlist, photos and notes.
                 Any new cars added since your backup will be preserved.
                 """)
        }

        // Reset confirmation
        .confirmationDialog("Reset All Data?",
                            isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all your cars, photos, and notes and reload the bundled catalogue. This cannot be undone.")
        }

        .confirmationDialog("Delete Community Account?",
                            isPresented: $showingDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    let ok = await socialFeedStore.deleteAccount()
                    operationStatus = (ok, ok ? "Community account deleted" : (socialFeedStore.lastError ?? "Account deletion failed"))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your community account and removes your posts and photos from the social feed. Your local checklist data is not deleted.")
        }

        // Share/export sheet
        .sheet(item: $backupFile) { file in
            ShareSheet(activityItems: [file.url])
                .onDisappear {
                    operationStatus = (true, "Backup created successfully")
                }
        }

        // Status toast
        .alert(
            operationStatus?.message ?? "",
            isPresented: Binding(
                get: { operationStatus != nil },
                set: { if !$0 { operationStatus = nil } }
            )
        ) { Button("OK") {} }

        // Busy overlay
        .overlay {
            if isProcessing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingUnlockSheet) {
            UnlockSheet().environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingAdminLogin) {
            SocialAdminLoginSheet(store: socialFeedStore) {
                showingAdminLogin = false
                showingAdminModeration = true
            }
        }
        .sheet(isPresented: $showingAdminModeration) {
            SocialAdminModerationView(store: socialFeedStore)
        }
        .sheet(isPresented: $showingAddCatalogModel) {
            AddCatalogModelSheet(store: socialFeedStore, dataManager: dataManager) { success, message in
                operationStatus = (success, message)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var dataManagementSection: some View {
        Section("Data Management") {
            if !devModeEnabled {
                Button {
                    guard !isProcessing && !isRefreshingCatalog else { return }
                    isRefreshingCatalog = true
                    Task {
                        let ok = await dataManager.refreshCatalogNow()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (ok, ok ? "Catalog refreshed" : "Refresh failed")
                        }
                    }
                } label: {
                    if isRefreshingCatalog {
                        HStack { ProgressView(); Text("Refreshing Catalog…") }
                    } else {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isProcessing || isRefreshingCatalog)
            } else {
                Text("Use Developer Mode below to refresh from your custom URL or toggle off to restore default.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Button {
                showingBackupAlert = true
            } label: { Label("Create Backup", systemImage: "arrow.up.doc") }
            .disabled(isProcessing)

            Button {
                showingRestorePicker = true
            } label: { Label("Restore Backup", systemImage: "arrow.down.doc") }
            .disabled(isProcessing)

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: { Label("Reset All Data", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        Section("Developer Mode") {
            Toggle(isOn: Binding(get: { devModeEnabled }, set: { newValue in
                if newValue {
                    // Taking a snapshot before entering Developer Mode
                    dataManager.createDeveloperSnapshot()
                    devModeEnabled = true
                } else {
                    // Leaving Developer Mode: restore snapshot and revert to default catalog
                    devModeEnabled = false
                    isRefreshingCatalog = true
                    Task {
                        await dataManager.restoreFromDeveloperSnapshot()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (true, "Restored your collection and default catalog")
                        }
                    }
                }
            })) {
                Text("Enable Developer Mode")
            }
            .disabled(isProcessing || isRefreshingCatalog)

            if devModeEnabled {
                TextField("Custom Catalog JSON URL", text: $devCatalogURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                Button {
                    guard !isProcessing && !isRefreshingCatalog else { return }
                    isRefreshingCatalog = true
                    Task {
                        let ok = await dataManager.refreshCatalogNow()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (ok, ok ? "Catalog refreshed from custom URL" : "Refresh failed")
                        }
                    }
                } label: {
                    if isRefreshingCatalog {
                        HStack { ProgressView(); Text("Refreshing Catalog…") }
                    } else {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isProcessing || isRefreshingCatalog || devCatalogURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("About Developer Mode")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text("Developer Mode is a safe sandbox for previewing catalogue changes. Any edits you make while it is on — including notes, photos, unboxed state, favourites, wishlist, and quantities — are temporary. When you turn Developer Mode off, your collection returns to its previous state.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var supportSection: some View {
        Section("Purchases") {
            if purchaseManager.isUnlocked {
                Label("Pro features unlocked", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            } else {
                Button {
                    showingUnlockSheet = true
                } label: {
                    Label("Unlock Pro", systemImage: "lock.open")
                }
            }

            Button {
                Task {
                    await purchaseManager.restore()
                    if purchaseManager.isUnlocked {
                        operationStatus = (true, "Purchase restored")
                    } else {
                        operationStatus = (false, "No purchase found")
                    }
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
        }
    }

    private var communitySection: some View {
        Section("Community") {
            if let viewedCollection {
                Button {
                    onCloseViewedCollection()
                } label: {
                    Label("Close \(viewedCollection.ownerName) Collection", systemImage: "xmark.circle")
                }
            }

            Link(destination: supportMailURL) {
                Label("Contact Support", systemImage: "envelope")
            }

            Link(destination: privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            if socialFeedStore.account != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who can view your collection?")
                        .font(.subheadline.weight(.semibold))
                    Picker(
                        "Who can view your collection?",
                        selection: Binding(
                            get: { socialFeedStore.account?.collectionVisibility ?? "friends" },
                            set: { visibility in
                                Task { await socialFeedStore.updateCollectionPrivacy(visibility) }
                            }
                        )
                    ) {
                        Text("Friends").tag("friends")
                        Text("Everyone").tag("everyone")
                        Text("No one").tag("none")
                    }
                    .pickerStyle(.segmented)
                    if socialFeedStore.isSavingPrivacy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving privacy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    socialFeedStore.requestPushNotifications()
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
            }

            Button {
                if socialFeedStore.isAdmin {
                    showingAdminModeration = true
                } else {
                    showingAdminLogin = true
                }
            } label: {
                Label(socialFeedStore.isAdmin ? "Moderation" : "Admin Login", systemImage: "shield.lefthalf.filled")
            }

            if socialFeedStore.isAdmin {
                Button {
                    showingAddCatalogModel = true
                } label: {
                    Label("Add Catalogue Car", systemImage: "plus.circle")
                }
            }

            if socialFeedStore.account != nil {
                Button(role: .destructive) {
                    showingDeleteAccountConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
    }


    private var aboutSection: some View {
        Section("About") {
            Label(appVersionText, systemImage: "info.circle")
            Label("Mattel Disney Pixar Cars Checklist", systemImage: "car.side.fill")
            Text("An unofficial collector project. Not affiliated with, endorsed by, or sponsored by Mattel, Disney, or Pixar.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Link("Catalogue source", destination: URL(string: "https://dpcarswiki.com/Special:VehicleDatabase")!)
            Link("Data licence (CC BY-SA 4.0)", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
        }
    }

    // MARK: - Actions

    private func createBackup() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let file = try await backupManager.createBackup(context: modelContext)
                backupFile = IdentifiableURL(url: file)
            } catch {
                operationStatus = (false, "Backup failed: \(error.localizedDescription)")
            }
        }
    }

    private func restoreBackup() {
        guard let file = restoreFile else { return }
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                restoreFile = nil
            }
            do {
                try await backupManager.restoreBackup(from: file, context: modelContext)
                operationStatus = (true, """
                Restore completed successfully.
                Your collection status, wishlist, photos and notes were restored.
                """)
                await MainActor.run {
                    dataManager.enforceStableIDs()          // optional but safe
                    dataManager.reloadFromPersistentStore()
                }
            } catch {
                operationStatus = (false, "Restore failed: \(error.localizedDescription)")
            }
        }
    }

    private func resetAllData() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            let success = await dataManager.resetAndReloadData()
            operationStatus = (success, success ? "Data reset successfully" : "Reset failed")
        }
    }
}

private struct AddCatalogModelSheet: View {
    @ObservedObject var store: SocialFeedStore
    @ObservedObject var dataManager: DataManager
    let onComplete: (Bool, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var payload = CatalogEditPayload(category: "Uncategorized", type: "1:55 Die-Cast")
    @State private var yearText = ""
    @State private var releaseCountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var addingNewCategory = false
    @State private var newCategory = ""

    private var categoryOptions: [String] {
        let values = dataManager.allModels
            .map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Name", text: $payload.name)
                    TextField("Catalogue ID (for example PCW-12345)", text: $payload.number)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    TextField("Product Code", text: $payload.productCode)
                    TextField("Character", text: $payload.character)
                    Picker("Format", selection: $payload.type) {
                        ForEach(catalogTypeOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Status", selection: $payload.status) {
                        ForEach(catalogStatusOptions, id: \.self) { status in
                            Text(status.isEmpty ? "None" : status).tag(status)
                        }
                    }
                    Picker("Category", selection: Binding(
                        get: { addingNewCategory ? "__add_new__" : payload.category },
                        set: { selected in
                            if selected == "__add_new__" {
                                addingNewCategory = true
                                newCategory = ""
                                payload.category = ""
                            } else {
                                addingNewCategory = false
                                newCategory = ""
                                payload.category = selected
                            }
                        }
                    )) {
                        ForEach((categoryOptions.isEmpty ? ["Uncategorized"] : categoryOptions), id: \.self) { Text($0).tag($0) }
                        Text("Add New Category").tag("__add_new__")
                    }
                    if addingNewCategory {
                        TextField("New Category", text: Binding(
                            get: { newCategory },
                            set: {
                                newCategory = $0
                                payload.category = $0
                            }
                        ))
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    }
                    TextField("Source Link", text: $payload.link)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .disableAutocorrection(true)
                }

                Section("Images & Links") {
                    TextField("Image Link", text: $payload.productImage)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .disableAutocorrection(true)
                }

                Section("Details") {
                    TextField("First Release Year", text: $yearText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Documented Releases", text: $releaseCountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Series", text: $payload.series)
                    TextEditor(text: $payload.modelDescription)
                        .frame(minHeight: 120)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        var draft = payload
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.number = draft.number.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.productCode = draft.productCode.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.character = draft.character.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.series = draft.series.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.productImage = draft.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.instructionsLink = draft.instructionsLink.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.threeSixtyView = draft.threeSixtyView.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.releaseDate = draft.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.modelDescription = draft.modelDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedYear = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedYear.isEmpty {
            draft.firstReleaseYear = nil
            draft.difficulty = nil
            draft.releaseDate = ""
        } else if let year = Int(trimmedYear), (2006...2100).contains(year) {
            draft.firstReleaseYear = year
            draft.difficulty = year
            draft.releaseDate = String(year)
        } else {
            errorMessage = "First release year must be blank or between 2006 and 2100."
            return
        }

        let trimmedCount = releaseCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCount.isEmpty {
            draft.releaseCount = 0
            draft.sheets = nil
        } else if let count = Int(trimmedCount), count >= 0 {
            draft.releaseCount = count
            draft.sheets = Double(count)
        } else {
            errorMessage = "Documented releases must be a non-negative whole number."
            return
        }

        guard !draft.name.isEmpty, !draft.number.isEmpty, !draft.category.isEmpty, !draft.link.isEmpty, !draft.type.isEmpty else {
            errorMessage = "Name, catalogue ID, format, category, and source link are required."
            return
        }

        Task {
            isSaving = true
            errorMessage = nil
            if let created = await store.createCatalogModel(draft) {
                dataManager.applyCatalogCreate(created)
                dismiss()
                onComplete(true, "Catalog model saved for everyone.")
            } else {
                errorMessage = store.lastError ?? "Catalog model could not be saved."
            }
            isSaving = false
        }
    }
}

private let catalogTypeOptions = [
    "1:55 Die-Cast",
    "Mini Racers",
    "Collector Exclusive",
    "Special Edition",
    "Premium / Larger Scale"
]

private let catalogStatusOptions = ["", "Coming Soon", "Exclusive", "Retired"]

private struct SocialAdminLoginSheet: View {
    @ObservedObject var store: SocialFeedStore
    let onAdminAuthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: SocialAuthenticationMode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedRules = false
    @State private var adminError: String?

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
                    Section("Community Guidelines") {
                        Text("Do not post abuse, harassment, hate, sexual content, illegal content, spam, scams, copyrighted images, personal information, threats, or bullying.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("Photo posts require admin approval before appearing in the public feed.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Link("Contact Support", destination: URL(string: "mailto:info@stonebrookstudios.co.uk")!)
                        Toggle("I accept the community rules", isOn: $acceptedRules)
                    }
                }

                if let adminError {
                    Section {
                        Text(adminError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                } else if let error = store.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Admin Login")
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
                            adminError = nil
                            let success = await store.authenticate(
                                mode: mode,
                                username: username,
                                email: email,
                                password: password,
                                acceptedRules: acceptedRules
                            )
                            if success && store.isAdmin {
                                onAdminAuthenticated()
                                dismiss()
                            } else if success {
                                adminError = "Admin account required."
                            }
                        }
                    } label: {
                        if store.isAuthenticating {
                            ProgressView()
                        } else {
                            Text(mode == .login ? "Log In" : "Create")
                        }
                    }
                    .disabled(store.isAuthenticating || (mode == .register && !acceptedRules))
                }
            }
        }
    }
}

private enum SocialAdminPostFilter: String, CaseIterable, Identifiable {
    case pending
    case reported
    case approved
    case rejected
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .reported: return "Reported"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .all: return "All"
        }
    }
}

private struct SocialAdminModerationView: View {
    @ObservedObject var store: SocialFeedStore

    @Environment(\.dismiss) private var dismiss
    @State private var tab = "posts"
    @State private var postFilter: SocialAdminPostFilter = .pending

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Moderation", selection: $tab) {
                    Text("Posts").tag("posts")
                    Text("Reports").tag("reports")
                    Text("Users").tag("users")
                }
                .pickerStyle(.segmented)
                .padding()

                if let error = store.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(error.lowercased().contains("blocked") ? .secondary : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                switch tab {
                case "reports":
                    reportsList
                case "users":
                    usersList
                default:
                    postsList
                }
            }
            .navigationTitle("Moderation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await refreshCurrentTab() }
                    } label: {
                        if store.isLoadingAdmin {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isLoadingAdmin)
                }
            }
            .task {
                await refreshCurrentTab()
            }
            .onChange(of: tab) { _, _ in
                Task { await refreshCurrentTab() }
            }
            .onChange(of: postFilter) { _, _ in
                Task { await store.loadAdminPosts(status: postFilter.rawValue) }
            }
        }
    }

    private var postsList: some View {
        VStack(spacing: 0) {
            Picker("Post Status", selection: $postFilter) {
                ForEach(SocialAdminPostFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if store.adminPosts.isEmpty {
                    Text("No posts in this queue.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.adminPosts) { post in
                        SocialAdminPostRow(post: post, isDisabled: store.isLoadingAdmin) { status in
                            Task {
                                await store.adminUpdatePostStatus(
                                    postID: post.id,
                                    status: status,
                                    visiblePostFilter: postFilter.rawValue
                                )
                            }
                        } onDelete: {
                            Task { await store.adminDeletePost(postID: post.id) }
                        }
                    }
                }
            }
        }
    }

    private var reportsList: some View {
        List {
            if store.adminReports.isEmpty {
                Text("No reports.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.adminReports) { report in
                    SocialAdminReportRow(report: report, isDisabled: store.isLoadingAdmin) { status in
                        if let postID = UUID(uuidString: report.postID) {
                            Task { await store.adminUpdatePostStatus(postID: postID, status: status) }
                        }
                    } onDelete: {
                        if let postID = UUID(uuidString: report.postID) {
                            Task { await store.adminDeletePost(postID: postID) }
                        }
                    }
                }
            }
        }
    }

    private var usersList: some View {
        List {
            if store.adminUsers.isEmpty {
                Text("No users.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.adminUsers) { user in
                    SocialAdminUserRow(user: user) { status in
                        Task { await store.adminUpdateUserStatus(userID: user.id, status: status) }
                    }
                }
            }
        }
    }

    private func refreshCurrentTab() async {
        switch tab {
        case "reports":
            await store.loadAdminReports()
        case "users":
            await store.loadAdminUsers()
        default:
            await store.loadAdminPosts(status: postFilter.rawValue)
        }
    }
}

private struct SocialAdminPostRow: View {
    let post: SocialFeedPost
    let isDisabled: Bool
    let onStatus: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(post.authorName)
                    .font(.subheadline.weight(.semibold))
                Text(post.status.capitalized)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
                if post.reportCount > 0 {
                    Label("\(post.reportCount)", systemImage: "flag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                }
                Spacer()
            }

            if !post.message.isEmpty {
                Text(post.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reason = post.moderationReason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let urlString = post.remoteImageURLString, let url = URL(string: urlString) {
                WebImage(url: url, options: [.scaleDownLargeImages]) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                Button("Approve") {
                    onStatus("approved")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                    .disabled(isDisabled || post.status == "approved")
                Button("Reject") {
                    onStatus("rejected")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .disabled(isDisabled || post.status == "rejected")
                Button("Hold") {
                    onStatus("pending")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .disabled(isDisabled || post.status == "pending")
                Spacer()
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                    .buttonStyle(.borderless)
                    .disabled(isDisabled)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch post.status {
        case "approved": return .green
        case "rejected": return .red
        case "pending": return .orange
        default: return .secondary
        }
    }
}

private struct SocialAdminReportRow: View {
    let report: SocialModerationReport
    let isDisabled: Bool
    let onStatus: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.authorName)
                    .font(.subheadline.weight(.semibold))
                Text(report.status.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                Spacer()
                Label("\(report.reportCount)", systemImage: "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
            }

            if !report.reason.isEmpty {
                Text(report.reason)
                    .font(.footnote.weight(.semibold))
            }

            if !report.message.isEmpty {
                Text(report.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Reported by \(report.reporterName)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Approve") {
                    onStatus("approved")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                    .disabled(isDisabled || report.status == "approved")
                Button("Reject") {
                    onStatus("rejected")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .disabled(isDisabled || report.status == "rejected")
                Button("Hold") {
                    onStatus("pending")
                }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .disabled(isDisabled || report.status == "pending")
                Spacer()
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                    .buttonStyle(.borderless)
                    .disabled(isDisabled)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
    }
}

private struct SocialAdminUserRow: View {
    let user: SocialModerationUser
    let onStatus: (String) -> Void
    @State private var showingStatusConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.username)
                        .font(.subheadline.weight(.semibold))
                    Text(user.role.capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(user.status.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundColor(user.status == "active" ? .green : .red)
            }

            Spacer()

            if user.status == "active" {
                Button(statusActionTitle, role: .destructive) {
                    showingStatusConfirmation = true
                }
                .buttonStyle(.bordered)
            } else {
                Button(statusActionTitle) {
                    showingStatusConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(statusConfirmationTitle, isPresented: $showingStatusConfirmation) {
            Button(statusActionTitle, role: user.status == "active" ? .destructive : nil) {
                onStatus(nextStatus)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(statusConfirmationMessage)
        }
    }

    private var nextStatus: String {
        user.status == "active" ? "suspended" : "active"
    }

    private var statusActionTitle: String {
        user.status == "active" ? "Suspend" : "Reactivate"
    }

    private var statusConfirmationTitle: String {
        user.status == "active" ? "Suspend User?" : "Reactivate User?"
    }

    private var statusConfirmationMessage: String {
        user.status == "active"
            ? "\(user.username) will be unable to sign in or use community features."
            : "\(user.username) will regain access to community features."
    }
}

// MARK: - Platform styling (keeps #if out of the main body)

private struct MacFormStyling: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 24)
            .background(Color.white)
        #else
        content
        #endif
    }
}

// MARK: - ShareSheet

#if os(iOS)
import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#else
import AppKit
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let activityItems: [Any]

    var body: some View {
        VStack(spacing: 16) {
            Text("Backup Created").font(.headline)

            if let url = activityItems.first as? URL {
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Copy Path") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(url.path, forType: .string)
                    }
                }
            }
            Button("Close") { dismiss() }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
#endif

// Helper
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

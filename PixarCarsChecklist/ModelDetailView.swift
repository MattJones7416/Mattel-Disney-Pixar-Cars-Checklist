import SwiftUI
import SwiftData
import Foundation
import SDWebImage
import SDWebImageSwiftUI

#if canImport(PhotosUI)
import PhotosUI     // enables PhotosPicker on macOS & Catalyst
#endif

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

struct ModelDetailView: View {
    let model: MetalModel
    @ObservedObject var dataManager: DataManager
    var isReadOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    @State private var noteText: String = ""
#if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
#endif

#if os(macOS) || targetEnvironment(macCatalyst)
    @State private var photoItem: PhotosPickerItem?
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var showAddPhotoOptions = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
#endif

    @State private var showDeleteAlert = false
    @State private var selectedPhotoToDelete: ModelPhoto?

    @State private var selectedPhotoFromDetail: ModelPhoto?
    @State private var currentIndexFromDetail: Int = 0

    @State private var sheetSelectedModel: MetalModel? = nil
    @State private var showingFullScreenProductImage = false

    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var socialFeedStore: SocialFeedStore
    @State private var showingUnlockSheet = false
    @State private var isEditingCatalog = false
    @State private var isSavingCatalogEdit = false
    @State private var activeCatalogEditField: CatalogEditField?
    @State private var draftCatalogPayload = CatalogEditPayload()
    @State private var catalogSaveError: String?
    @State private var showingCatalogSaveError = false
    @State private var catalogRestrictionMessage: String?
    @State private var showingCatalogRestriction = false

#if os(iOS)
    private var isiOSAppOnMac: Bool {
        if #available(iOS 14.0, *) {
            // keep original behavior and add the extra flag
            return UIDevice.current.userInterfaceIdiom == .mac
            || ProcessInfo.processInfo.isiOSAppOnMac
        }
        return UIDevice.current.userInterfaceIdiom == .mac
    }
#endif


    private var photos: [ModelPhoto] {
        guard !isReadOnly else { return [] }
        return dataManager.getPhotos(for: model)
    }

    private var note: ModelNote? {
        guard !isReadOnly else { return nil }
        return dataManager.getNote(for: model)
    }

    // Platform-safe backgrounds (iPhone uses the originals)
    private var groupedBG: Color {
#if os(iOS) || targetEnvironment(macCatalyst)
        Color(.systemGroupedBackground)
#else
        Color(NSColor.windowBackgroundColor)
#endif
    }
    private var secondaryBG: Color {
#if os(iOS) || targetEnvironment(macCatalyst)
        Color(.secondarySystemBackground)
#else
        Color(NSColor.underPageBackgroundColor)
#endif
    }

    // MARK: - ModelDetailView image resolvers
    private var resolvedDetailRemoteURL: URL? {
        let prod = activeCatalogPayload.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prod.isEmpty else { return nil }
        if prod.lowercased().starts(with: "http"), let url = URL(string: prod) {
            return url
        }
        return nil
    }

    private var resolvedDetailBundleImageCandidates: [String] {
        bundleImageCandidates(for: model)
    }

    private var activeCatalogPayload: CatalogEditPayload {
        isEditingCatalog ? draftCatalogPayload : CatalogEditPayload(model: model)
    }

    private var canEditCatalog: Bool {
        !isReadOnly && socialFeedStore.isAdmin
    }


    var body: some View {
        let catalog = activeCatalogPayload
        NavigationStack {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // Header
                VStack(alignment: .center, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(catalog.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .onTapGesture {
                                if isEditingCatalog {
                                    requestCatalogEdit(.name)
                                }
                            }

                        if !catalog.link.isEmpty || isEditingCatalog {
                            Button {
                                if isEditingCatalog {
                                    requestCatalogEdit(.link)
                                } else {
                                    openExternalURL(catalog.link)
                                }
                            } label: {
                                Image(systemName: "link.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open source page")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text(catalog.number)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            if isEditingCatalog {
                                requestCatalogEdit(.number)
                            }
                        }

                    if !catalog.status.isEmpty || isEditingCatalog {
                        Text(catalog.status.isEmpty ? "Status" : catalog.status)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(statusColor(for: catalog.status))
                            .padding(.top, 2)
                            .onTapGesture {
                                if isEditingCatalog {
                                    requestCatalogEdit(.status)
                                }
                            }
                    }
                }
                .padding(.horizontal)

                DetailProductImageView(
                    remoteURL: resolvedDetailRemoteURL,
                    bundleImageCandidates: resolvedDetailBundleImageCandidates
                ) {
                    if isEditingCatalog {
                        requestCatalogEdit(.productImage)
                    } else {
                        showingFullScreenProductImage = true
                    }
                }
                .padding(.horizontal)

                DetailUserActionBar(
                    model: model,
                    dataManager: dataManager,
                    isUnlocked: purchaseManager.isUnlocked,
                    accentColor: Color(hex: "D92D20"),
                    isReadOnly: isReadOnly,
                    onCollectionChanged: onCollectionChanged
                ) {
                    showingUnlockSheet = true
                }
                .padding(.horizontal)

                DetailModelInfoPanel(
                    catalog: catalog,
                    background: groupedBG,
                    editMode: isEditingCatalog,
                    editField: { requestCatalogEdit($0) },
                    openInstructions: {
                        openExternalURL(catalog.instructionsLink)
                    },
                    openThreeSixty: {
                        openExternalURL(catalog.threeSixtyView)
                    }
                )
                .padding(.horizontal)

                // Description (unchanged)
                if !catalog.modelDescription.isEmpty || isEditingCatalog {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Catalogue Notes")
                            .font(.headline)
                        Text(catalog.modelDescription.isEmpty ? "Tap to add a description" : catalog.modelDescription)
                            .font(.body)
                            .foregroundColor(catalog.modelDescription.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                if isEditingCatalog {
                                    requestCatalogEdit(.description)
                                }
                            }
                    }
                    .padding()
                    .background(groupedBG)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Photos section: iPhone keeps camera sheet; Mac/Catalyst uses PhotosPicker
                VStack(alignment: .leading) {
                    HStack {
                        // Lock badge in header (leading)
                        if !isReadOnly && !purchaseManager.isUnlocked {
                            SubtleLockBadge()
                                .onTapGesture { showingUnlockSheet = true }
                        }
                        Text("Photos")
                            .font(.headline)

                        Spacer()

                        #if os(iOS) && !targetEnvironment(macCatalyst)
                        if !isReadOnly {
                            Button {
                                if purchaseManager.isUnlocked {
                                    showAddPhotoOptions = true
                                } else {
                                    showingUnlockSheet = true
                                }
                            } label: {
                                Image(systemName: "camera").font(.headline)
                            }
                            .disabled(!purchaseManager.isUnlocked)
                            .confirmationDialog("Add Photo", isPresented: $showAddPhotoOptions, titleVisibility: .visible) {
                                // Only offer camera on iPhone/iPad hardware
                                if !isiOSAppOnMac && UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button("Take Photo") {
                                        imagePickerSource = .camera
                                        showImagePicker = true
                                    }
                                }
                                Button("Choose from Library") {
                                    imagePickerSource = .photoLibrary
                                    showImagePicker = true
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                        #endif
                    }

                    if photos.isEmpty {
                        ZStack {
                            Text(isReadOnly ? "Photos are private" : "No photos yet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()

                            // Locked overlay CTA when empty
                            if !isReadOnly && !purchaseManager.isUnlocked {
                                VStack {
                                    Spacer()
                                    Button {
                                        showingUnlockSheet = true
                                    } label: {
                                        VStack(spacing: 6) {
                                            SubtleLockBadge(size: 20)
                                                Text("Unlock to add photos")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(12)
                                        .background(Color(.systemBackground).opacity(0.9))
                                        .cornerRadius(10)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        ZStack(alignment: .center) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(photos, id: \.id) { photo in
                    #if os(iOS) || targetEnvironment(macCatalyst)
                                        if let uiImage = UIImage(data: photo.imageData) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 150, height: 150)
                                                    .cornerRadius(8)
                                                    .clipped()
                                                    .onTapGesture {
                                                if isReadOnly {
                                                    return
                                                }
                                                if purchaseManager.isUnlocked {
                                                    selectedPhotoFromDetail = photo
                                                        } else {
                                                            showingUnlockSheet = true
                                                        }
                                                    }

                                                Button {
                                                    if isReadOnly {
                                                        return
                                                    }
                                                    if purchaseManager.isUnlocked {
                                                        selectedPhotoToDelete = photo
                                                        showDeleteAlert = true
                                                    } else {
                                                        showingUnlockSheet = true
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .padding(4)
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(isReadOnly || !purchaseManager.isUnlocked)
                                            }
                                        }
                    #else
                                        if let nsImage = NSImage(data: photo.imageData) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 150, height: 150)
                                                    .cornerRadius(8)
                                                    .clipped()
                                                    .onTapGesture {
                                                        if isReadOnly {
                                                            return
                                                        }
                                                        if purchaseManager.isUnlocked {
                                                            selectedPhotoFromDetail = photo
                                                        } else {
                                                            showingUnlockSheet = true
                                                        }
                                                    }

                                                Button {
                                                    if isReadOnly {
                                                        return
                                                    }
                                                    if purchaseManager.isUnlocked {
                                                        selectedPhotoToDelete = photo
                                                        showDeleteAlert = true
                                                    } else {
                                                        showingUnlockSheet = true
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .padding(4)
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(isReadOnly || !purchaseManager.isUnlocked)
                                            }
                                        }
                    #endif
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 2)
                            }

                            // Dim overlay + center CTA when locked
                            if !isReadOnly && !purchaseManager.isUnlocked {
                                Color.black.opacity(0.06)
                                    .cornerRadius(8)
                                    .ignoresSafeArea(.container, edges: .horizontal)

                                VStack(spacing: 8) {
                                    SubtleLockBadge(size: 22)
                                    Text("Unlock to view photos")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Button("Unlock") { showingUnlockSheet = true }
                                        .buttonStyle(.borderedProminent)
                                        .padding(.top, 6)
                                }
                                .padding()
                                .background(.regularMaterial)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding()
                .background(groupedBG)
                .cornerRadius(10)
                .padding(.horizontal)

                .alert("Delete this photo?", isPresented: $showDeleteAlert, presenting: selectedPhotoToDelete) { photo in
                    Button("Delete", role: .destructive) {
                        if let photo = selectedPhotoToDelete {
                            guard !isReadOnly else { return }
                            dataManager.deletePhoto(photo)
                            selectedPhotoToDelete = nil
                            showDeleteAlert = false // FIX: Ensure alert is dismissed
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        // FIX: Properly clear all related states
                        selectedPhotoToDelete = nil
                        showDeleteAlert = false
                    }
                } message: { photo in
                    Text("Are you sure you want to delete this photo?")
                }

                // Notes (locked/unlocked) — matches Photos overlay style with centered CTA
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if !isReadOnly && !purchaseManager.isUnlocked {
                            SubtleLockBadge()
                                .onTapGesture { showingUnlockSheet = true }
                        }
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                    }

                    ZStack {
                        // The actual editor (read-only when locked)
                        TextEditor(text: $noteText)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(secondaryBG)
                            .cornerRadius(8)
                            .onAppear { noteText = isReadOnly ? "Notes are private" : (note?.text ?? "") }
                            .onChange(of: noteText) { _, newValue in
                                guard !isReadOnly else {
                                    noteText = "Notes are private"
                                    return
                                }
                                if purchaseManager.isUnlocked {
                                    dataManager.updateNote(for: model, text: newValue)
                                } else {
                                    // revert edits locally (do not save)
                                    noteText = note?.text ?? ""
                                }
                            }
                            .disabled(isReadOnly || !purchaseManager.isUnlocked)
                            .opacity((isReadOnly || purchaseManager.isUnlocked) ? 1.0 : 0.95)

                        // Overlay when locked (identical to Photos style)
                        if !isReadOnly && !purchaseManager.isUnlocked {
                            Color.black.opacity(0.06)
                                .cornerRadius(8)
                                .allowsHitTesting(false)

                            VStack(spacing: 6) {
                                SubtleLockBadge(size: 20)
                                Text("Unlock to add notes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color(.systemBackground).opacity(0.9))
                            .cornerRadius(10)
                            .onTapGesture { showingUnlockSheet = true }
                        }
                    }
                }
                .padding()
                .background(groupedBG)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 60)
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingUnlockSheet) {
            UnlockSheet().environmentObject(purchaseManager)
        }
        .sheet(item: $activeCatalogEditField) { field in
            CatalogEditFieldEditor(field: field, payload: draftCatalogPayload, categories: catalogCategoryOptions) { updated in
                draftCatalogPayload = updated
            }
        }
        .sheet(item: $selectedPhotoFromDetail) { tappedPhoto in
            ModelDetailPhotoHost(
                model: model,
                tappedPhoto: tappedPhoto,
                dataManager: dataManager,
                parentSelectedPhoto: $selectedPhotoFromDetail
            )
        }
        #if os(iOS) || targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingFullScreenProductImage) {
            FullScreenProductImageView(
                remoteURL: resolvedDetailRemoteURL,
                bundleImageCandidates: resolvedDetailBundleImageCandidates
            ) {
                showingFullScreenProductImage = false
            }
        }
        #else
        .sheet(isPresented: $showingFullScreenProductImage) {
            FullScreenProductImageView(
                remoteURL: resolvedDetailRemoteURL,
                bundleImageCandidates: resolvedDetailBundleImageCandidates
            ) {
                showingFullScreenProductImage = false
            }
            .frame(minWidth: 720, minHeight: 620)
        }
        #endif

                // Titles by platform (keeps iPhone inline title)
                #if os(iOS) || targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
                #else
                .navigationTitle(model.name)
                #endif
                .toolbar {
                    if canEditCatalog {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if isEditingCatalog {
                                Button {
                                    saveCatalogEdit()
                                } label: {
                                    if isSavingCatalogEdit {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .disabled(isSavingCatalogEdit)

                                Button(role: .cancel) {
                                    draftCatalogPayload = CatalogEditPayload(model: model)
                                    activeCatalogEditField = nil
                                    isEditingCatalog = false
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .disabled(isSavingCatalogEdit)
                            } else {
                                Button {
                                    draftCatalogPayload = CatalogEditPayload(model: model)
                                    isEditingCatalog = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                            }
                        }
                    }
                }
                .alert("Catalog Save Failed", isPresented: $showingCatalogSaveError) {
                    Button("OK") {}
                } message: {
                    Text(catalogSaveError ?? "Catalog edit failed.")
                }
                .alert("Restricted", isPresented: $showingCatalogRestriction) {
                    Button("OK") {}
                } message: {
                    Text(catalogRestrictionMessage ?? "Restricted to admin users.")
                }

                // iPhone camera sheet
                #if os(iOS) && !targetEnvironment(macCatalyst)
                .sheet(isPresented: $showImagePicker, onDismiss: loadImage) {
                    ImagePicker(image: $inputImage, sourceType: imagePickerSource)
                }
                #endif

                // Mac/Catalyst PhotosPicker handler
                #if (os(macOS) || targetEnvironment(macCatalyst)) && canImport(PhotosUI)
                .onChange(of: photoItem) { _, newItem in
                    guard !isReadOnly else {
                        photoItem = nil
                        return
                    }
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            dataManager.addPhoto(for: model, imageData: data)
                        }
                        photoItem = nil
                    }
                }
                #endif
            }
        }

    // MARK: - Helpers
    private var catalogCategoryOptions: [String] {
        Array(Set(dataManager.allModels.map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func requestCatalogEdit(_ field: CatalogEditField) {
        guard !isReadOnly else { return }
        guard canEditCatalog else {
            catalogRestrictionMessage = "Catalogue editing is restricted to administrators."
            showingCatalogRestriction = true
            return
        }
        activeCatalogEditField = field
    }

    private func saveCatalogEdit() {
        guard !isReadOnly else { return }
        guard !isSavingCatalogEdit else { return }
        Task {
            isSavingCatalogEdit = true
            let original = CatalogEditPayload(model: model)
            if let updated = await socialFeedStore.updateCatalogModel(original: original, edited: draftCatalogPayload) {
                dataManager.applyCatalogEdit(to: model, payload: updated)
                draftCatalogPayload = updated
                activeCatalogEditField = nil
                isEditingCatalog = false
                isSavingCatalogEdit = false
            } else {
                catalogSaveError = socialFeedStore.lastError ?? "Catalog edit failed."
                showingCatalogSaveError = true
                isSavingCatalogEdit = false
            }
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(iOS) || targetEnvironment(macCatalyst)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func loadImage() {
        guard !isReadOnly else {
            inputImage = nil
            return
        }
        guard let inputImage,
              let data = inputImage.jpegData(compressionQuality: 0.8) else { return }
        dataManager.addPhoto(for: model, imageData: data)
        self.inputImage = nil
    }
    #endif
}

private func statusColor(for status: String) -> Color {
    switch status {
    case "Retired": return .red
    case "Exclusive": return .blue
    case "Coming Soon": return .green
    default: return .primary
    }
}

private enum CatalogEditField: String, Identifiable {
    case name
    case number
    case productCode
    case character
    case firstReleaseYear
    case releaseCount
    case series
    case link
    case productImage
    case category
    case type
    case status
    case difficulty
    case sheets
    case releaseDate
    case instructionsLink
    case threeSixtyView
    case description

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .number: return "Catalogue ID"
        case .productCode: return "Product Code"
        case .character: return "Character"
        case .firstReleaseYear: return "First Release Year"
        case .releaseCount: return "Documented Releases"
        case .series: return "Series"
        case .link: return "Source Link"
        case .productImage: return "Image Link"
        case .category: return "Category"
        case .type: return "Format"
        case .status: return "Status"
        case .difficulty: return "Legacy Year"
        case .sheets: return "Legacy Release Count"
        case .releaseDate: return "Release Date"
        case .instructionsLink: return "Instructions Link"
        case .threeSixtyView: return "360 View Link"
        case .description: return "Description"
        }
    }

    var isMultiline: Bool {
        self == .description
    }
}

private struct CatalogEditFieldEditor: View {
    let field: CatalogEditField
    let payload: CatalogEditPayload
    let categories: [String]
    let onSave: (CatalogEditPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var addingNewCategory = false
    @State private var newCategory = ""

    init(field: CatalogEditField, payload: CatalogEditPayload, categories: [String], onSave: @escaping (CatalogEditPayload) -> Void) {
        self.field = field
        self.payload = payload
        self.categories = categories
        self.onSave = onSave
        _value = State(initialValue: payload.value(for: field))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch field {
                    case .type:
                        Picker("Format", selection: $value) {
                            ForEach(detailCatalogTypeOptions, id: \.self) { Text($0).tag($0) }
                        }
                    case .status:
                        Picker("Status", selection: $value) {
                            ForEach(detailCatalogStatusOptions, id: \.self) { status in
                                Text(status.isEmpty ? "None" : status).tag(status)
                            }
                        }
                    case .category:
                        Picker("Category", selection: Binding(
                            get: { addingNewCategory ? "__add_new__" : value },
                            set: { selected in
                                if selected == "__add_new__" {
                                    addingNewCategory = true
                                    newCategory = ""
                                    value = ""
                                } else {
                                    addingNewCategory = false
                                    newCategory = ""
                                    value = selected
                                }
                            }
                        )) {
                            ForEach((categories.isEmpty ? ["Uncategorized"] : categories), id: \.self) { Text($0).tag($0) }
                            Text("Add New Category").tag("__add_new__")
                        }
                        if addingNewCategory {
                            TextField("New Category", text: Binding(
                                get: { newCategory },
                                set: { newValue in
                                    newCategory = newValue
                                    value = newValue
                                }
                            ))
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                        }
                    default:
                        if field.isMultiline {
                            TextEditor(text: $value)
                                .frame(minHeight: 180)
                        } else {
                            TextField(field.title, text: $value)
                        }
                    }
                }
            }
            .navigationTitle("Edit \(field.title)")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(payload.updating(field, value: value))
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension CatalogEditPayload {
    func value(for field: CatalogEditField) -> String {
        switch field {
        case .name: return name
        case .number: return number
        case .productCode: return productCode
        case .character: return character
        case .firstReleaseYear: return firstReleaseYear.map(String.init) ?? ""
        case .releaseCount: return releaseCount > 0 ? String(releaseCount) : ""
        case .series: return series
        case .link: return link
        case .productImage: return productImage
        case .category: return category
        case .type: return type
        case .status: return status
        case .difficulty: return difficulty.map(String.init) ?? ""
        case .sheets:
            guard let sheets else { return "" }
            return sheets.rounded(.towardZero) == sheets ? "\(Int(sheets))" : "\(sheets)"
        case .releaseDate: return releaseDate
        case .instructionsLink: return instructionsLink
        case .threeSixtyView: return threeSixtyView
        case .description: return modelDescription
        }
    }

    func updating(_ field: CatalogEditField, value rawValue: String) -> CatalogEditPayload {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var copy = self
        switch field {
        case .name: copy.name = trimmed
        case .number: copy.number = trimmed
        case .productCode: copy.productCode = trimmed
        case .character: copy.character = trimmed
        case .firstReleaseYear:
            copy.firstReleaseYear = Int(trimmed)
            copy.difficulty = Int(trimmed)
            copy.releaseDate = trimmed
        case .releaseCount:
            copy.releaseCount = Int(trimmed) ?? 0
            copy.sheets = Double(copy.releaseCount)
        case .series: copy.series = trimmed
        case .link: copy.link = trimmed
        case .productImage: copy.productImage = trimmed
        case .category: copy.category = trimmed
        case .type: copy.type = trimmed
        case .status: copy.status = trimmed
        case .difficulty: copy.difficulty = Int(trimmed)
        case .sheets: copy.sheets = Double(trimmed)
        case .releaseDate: copy.releaseDate = trimmed
        case .instructionsLink: copy.instructionsLink = trimmed
        case .threeSixtyView: copy.threeSixtyView = trimmed
        case .description: copy.modelDescription = trimmed
        }
        return copy
    }
}

private let detailCatalogTypeOptions = [
    "1:55 Die-Cast",
    "Mini Racers",
    "Collector Exclusive",
    "Special Edition",
    "Premium / Larger Scale"
]

private let detailCatalogStatusOptions = ["", "Coming Soon", "Exclusive", "Retired"]

private let detailPreviewThumbnailPixelSize = CGSize(width: 900, height: 900)

private struct DetailProductImageView: View {
    let remoteURL: URL?
    let bundleImageCandidates: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.08))

                Group {
                    if let remoteURL {
                        DetailRemoteProductImage(url: remoteURL)
                    } else {
                        DetailLocalProductImage(candidates: bundleImageCandidates)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full screen image")
    }
}

private struct DetailRemoteProductImage: View {
    let url: URL
    @State private var didFail = false

    var body: some View {
        Group {
            if didFail {
                DetailImagePlaceholder()
            } else {
                WebImage(
                    url: url,
                    options: [.lowPriority, .scaleDownLargeImages],
                    context: [.imageThumbnailPixelSize: detailPreviewThumbnailPixelSize]
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .onFailure { _ in
                    didFail = true
                }
            }
        }
    }
}

private struct DetailLocalProductImage: View {
    @StateObject private var loader: MEBundleImageLoader

    init(candidates: [String]) {
        _loader = StateObject(wrappedValue: MEBundleImageLoader(candidates: candidates))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                platformImage(image)
                    .resizable()
                    .scaledToFit()
            } else {
                DetailImagePlaceholder()
            }
        }
        .onAppear { loader.load() }
    }

    private func platformImage(_ image: MEPlatformImage) -> Image {
        #if os(iOS)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
        #endif
    }
}

private struct DetailImagePlaceholder: View {
    var body: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray)
            .opacity(0.45)
            .frame(maxWidth: .infinity, maxHeight: 120)
    }
}

private struct DetailUserActionBar: View {
    let model: MetalModel
    @ObservedObject var dataManager: DataManager
    let isUnlocked: Bool
    let accentColor: Color
    let isReadOnly: Bool
    let onCollectionChanged: () -> Void
    let requestUnlock: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            DetailActionButton(
                systemImage: "checkmark",
                symbol: nil,
                isActive: model.checked,
                activeColor: accentColor,
                isLocked: false,
                badgeText: nil,
                accessibilityLabel: model.checked ? "Mark uncollected" : "Mark collected"
            ) {
                guard !isReadOnly else { return }
                dataManager.toggleChecked(for: model)
                onCollectionChanged()
            }

            DetailActionButton(
                systemImage: "shippingbox",
                symbol: nil,
                isActive: model.built,
                activeColor: .blue,
                isLocked: !isReadOnly && !isUnlocked,
                badgeText: nil,
                accessibilityLabel: model.built ? "Mark carded" : "Mark unboxed"
            ) {
                guard !isReadOnly else { return }
                if isUnlocked {
                    dataManager.toggleBuilt(for: model)
                    onCollectionChanged()
                } else {
                    requestUnlock()
                }
            }

            DetailActionButton(
                systemImage: model.isFavorite ? "star.fill" : "star",
                symbol: nil,
                isActive: model.isFavorite,
                activeColor: .yellow,
                isLocked: !isReadOnly && !isUnlocked,
                badgeText: nil,
                accessibilityLabel: model.isFavorite ? "Remove favorite" : "Add favorite"
            ) {
                guard !isReadOnly else { return }
                if isUnlocked {
                    dataManager.toggleFavorite(for: model)
                    onCollectionChanged()
                } else {
                    requestUnlock()
                }
            }

            DetailActionButton(
                systemImage: model.isWishlisted ? "gift.fill" : "gift",
                symbol: nil,
                isActive: model.isWishlisted,
                activeColor: .pink,
                isLocked: !isReadOnly && !isUnlocked,
                badgeText: nil,
                accessibilityLabel: model.isWishlisted ? "Remove wishlist" : "Add wishlist"
            ) {
                guard !isReadOnly else { return }
                if isUnlocked {
                    dataManager.toggleWishlist(for: model)
                    onCollectionChanged()
                } else {
                    requestUnlock()
                }
            }

            if isReadOnly {
                DetailActionButton(
                    systemImage: nil,
                    symbol: "#",
                    isActive: model.quantity > 0,
                    activeColor: .teal,
                    isLocked: false,
                    badgeText: model.quantity > 0 ? "\(model.quantity)" : nil,
                    accessibilityLabel: "Quantity"
                ) {}
            } else if isUnlocked {
                Menu {
                    ForEach(1..<11, id: \.self) { quantity in
                        Button {
                            dataManager.updateQuantity(for: model, quantity: quantity)
                            onCollectionChanged()
                        } label: {
                            if quantity == model.quantity {
                                Label("Quantity: \(quantity)", systemImage: "checkmark")
                            } else {
                                Text("Quantity: \(quantity)")
                            }
                        }
                    }
                } label: {
                    DetailActionButtonLabel(
                        systemImage: nil,
                        symbol: "#",
                        isActive: model.quantity > 0,
                        activeColor: .teal,
                        isLocked: false,
                        badgeText: model.quantity > 0 ? "\(model.quantity)" : nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change quantity")
            } else {
                DetailActionButton(
                    systemImage: nil,
                    symbol: "#",
                    isActive: model.quantity > 0,
                    activeColor: .teal,
                    isLocked: true,
                    badgeText: model.quantity > 0 ? "\(model.quantity)" : nil,
                    accessibilityLabel: "Unlock quantity"
                ) {
                    requestUnlock()
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct DetailActionButton: View {
    let systemImage: String?
    let symbol: String?
    let isActive: Bool
    let activeColor: Color
    let isLocked: Bool
    let badgeText: String?
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailActionButtonLabel(
                systemImage: systemImage,
                symbol: symbol,
                isActive: isActive,
                activeColor: activeColor,
                isLocked: isLocked,
                badgeText: badgeText
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DetailActionButtonLabel: View {
    let systemImage: String?
    let symbol: String?
    let isActive: Bool
    let activeColor: Color
    let isLocked: Bool
    let badgeText: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? activeColor.opacity(0.20) : detailInactiveButtonFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isActive ? activeColor.opacity(0.42) : detailButtonStrokeColor, lineWidth: 1)
                )

            icon
                .foregroundColor(isActive ? activeColor : .secondary)
                .frame(width: 48, height: 48)

            if let badgeText {
                Text(badgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(activeColor)
                    .clipShape(Capsule())
                    .offset(x: 4, y: -5)
            }

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.gray.opacity(0.85))
                    .padding(4)
                    .background(Color.gray.opacity(0.18))
                    .clipShape(Circle())
                    .offset(x: 5, y: -6)
            }
        }
        .frame(width: 48, height: 48)
    }

    @ViewBuilder
    private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
        } else if let symbol {
            Text(symbol)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
    }
}

private var detailInactiveButtonFill: Color {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return Color(.secondarySystemBackground).opacity(0.9)
    #else
    return Color(NSColor.underPageBackgroundColor).opacity(0.9)
    #endif
}

private var detailButtonStrokeColor: Color {
    Color.primary.opacity(0.08)
}

private struct DetailModelInfoPanel: View {
    let catalog: CatalogEditPayload
    let background: Color
    let editMode: Bool
    let editField: (CatalogEditField) -> Void
    let openInstructions: () -> Void
    let openThreeSixty: () -> Void

    private var hasActionLinks: Bool {
        !catalog.instructionsLink.isEmpty || !catalog.threeSixtyView.isEmpty || editMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                if !catalog.productCode.isEmpty || editMode {
                    DetailInfoChip(systemImage: "number", title: "Product Code", value: catalog.productCode.isEmpty ? "Add" : catalog.productCode) {
                        if editMode { editField(.productCode) }
                    }
                }

                if !catalog.character.isEmpty || editMode {
                    DetailInfoChip(systemImage: "person.crop.circle", title: "Character", value: catalog.character.isEmpty ? "Add" : catalog.character) {
                        if editMode { editField(.character) }
                    }
                }

                if !catalog.series.isEmpty || editMode {
                    DetailInfoChip(systemImage: "rectangle.stack", title: "Series", value: catalog.series.isEmpty ? "Add" : catalog.series) {
                        if editMode { editField(.series) }
                    }
                }

                if !catalog.category.isEmpty || editMode {
                    DetailInfoChip(systemImage: "folder", title: "Category", value: catalog.category.isEmpty ? "Add" : catalog.category) {
                        if editMode { editField(.category) }
                    }
                }

                DetailInfoChip(systemImage: "car.side", title: "Format", value: catalog.type.isEmpty ? "1:55 Die-Cast" : catalog.type) {
                    if editMode { editField(.type) }
                }

                if let year = catalog.firstReleaseYear ?? Int(catalog.releaseDate) {
                    DetailInfoChip(systemImage: "calendar", title: "First Released", value: String(year)) {
                        if editMode { editField(.firstReleaseYear) }
                    }
                } else if editMode {
                    DetailInfoChip(systemImage: "calendar", title: "First Released", value: "Add") {
                        editField(.firstReleaseYear)
                    }
                }

                if catalog.releaseCount > 0 || editMode {
                    DetailInfoChip(systemImage: "square.stack.3d.up", title: "Releases", value: catalog.releaseCount > 0 ? String(catalog.releaseCount) : "Add") {
                        if editMode { editField(.releaseCount) }
                    }
                }
            }

            if hasActionLinks {
                Divider()

                HStack(spacing: 10) {
                    if !catalog.instructionsLink.isEmpty || editMode {
                        DetailLinkButton(title: "Instructions", systemImage: "doc.text") {
                            if editMode {
                                editField(.instructionsLink)
                            } else {
                                openInstructions()
                            }
                        }
                    }

                    if !catalog.threeSixtyView.isEmpty || editMode {
                        DetailLinkButton(title: "360 View", systemImage: "view.3d") {
                            if editMode {
                                editField(.threeSixtyView)
                            } else {
                                openThreeSixty()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DetailInfoChip: View {
    let systemImage: String
    let title: String
    let value: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    chipContent
                }
                .buttonStyle(.plain)
            } else {
                chipContent
            }
        }
    }

    private var chipContent: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailLinkButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FullScreenProductImageView: View {
    let remoteURL: URL?
    let bundleImageCandidates: [String]
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if let remoteURL {
                    FullResolutionRemoteImage(url: remoteURL)
                } else {
                    FullResolutionLocalImage(candidates: bundleImageCandidates)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close image")
            .padding(18)
        }
    }
}

private struct FullResolutionRemoteImage: View {
    let url: URL
    @State private var didFail = false

    var body: some View {
        Group {
            if didFail {
                DetailImagePlaceholder()
                    .foregroundColor(.white.opacity(0.7))
            } else {
                WebImage(url: url, options: [.highPriority, .retryFailed]) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onFailure { _ in
                    didFail = true
                }
            }
        }
    }
}

private struct FullResolutionLocalImage: View {
    @StateObject private var loader: MEBundleImageLoader

    init(candidates: [String]) {
        _loader = StateObject(wrappedValue: MEBundleImageLoader(candidates: candidates))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                platformImage(image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear { loader.load() }
    }

    private func platformImage(_ image: MEPlatformImage) -> Image {
        #if os(iOS)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
        #endif
    }
}

// Small reusable lock badge used when feature is locked
struct SubtleLockBadge: View {
    var size: CGFloat = 11
    var body: some View {
        Image(systemName: "lock")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(Color.gray.opacity(0.8))
            .padding(6)
            .background(Color(.systemGray5))
            .clipShape(Circle())
    }
}


// MARK: - Host used by ModelDetailView.sheet to give PhotoDetailView writable state
private struct ModelDetailPhotoHost: View {
    let model: MetalModel
    let tappedPhoto: ModelPhoto
    @ObservedObject var dataManager: DataManager
    @Binding var parentSelectedPhoto: ModelPhoto?

    @State private var photos: [ModelPhoto]
    @State private var currentIndex: Int

    init(model: MetalModel, tappedPhoto: ModelPhoto, dataManager: DataManager, parentSelectedPhoto: Binding<ModelPhoto?>) {
        self.model = model
        self.tappedPhoto = tappedPhoto
        self.dataManager = dataManager
        self._parentSelectedPhoto = parentSelectedPhoto

        // build initial photo list from dataManager so we have writable local state
        let modelPhotos = dataManager.getPhotos(for: model)

        self._photos = State(initialValue: modelPhotos)
        self._currentIndex = State(initialValue: modelPhotos.firstIndex { $0.id == tappedPhoto.id } ?? 0)
    }

    var body: some View {
        // build a single-string id from all photo UUIDs (keeps it stable until photos change)
        let photosID = photos.map { $0.id.uuidString }.joined(separator: "-")

        PhotoDetailView(
            model: model,
            photos: $photos,
            currentIndex: $currentIndex,
            dataManager: dataManager,
            onClose: {
                parentSelectedPhoto = nil
            },
            onOpenModel: {
                // close the sheet; outer UI can handle navigation if needed
                parentSelectedPhoto = nil
            },
            showsModelControls: false
        )
        .id(photosID) // FORCE recreation when photos list changes
        .onReceive(NotificationCenter.default.publisher(for: .init("RefreshPhotosForModel_\(model.id)"))) { _ in
            // Optional: keep host in sync if something else posts this notification
            let modelPhotos = dataManager.getPhotos(for: model)
            photos = modelPhotos
            if currentIndex >= photos.count {
                currentIndex = max(0, photos.count - 1)
            }
        }
    }
}


// MARK: - iOS-only ImagePicker (unchanged)
#if os(iOS) && !targetEnvironment(macCatalyst)
struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary   // ← NEW

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType                                    // ← NEW
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        // Optional but nice to have:
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
#endif

import SwiftUI
import SwiftData
import Foundation

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

    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingUnlockSheet = false

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
        dataManager.allPhotos
            .filter { $0.modelId == model.id }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var note: ModelNote? {
        dataManager.getNote(for: model)
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
        let prod = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prod.isEmpty else { return nil }
        if prod.lowercased().starts(with: "http"), let url = URL(string: prod) {
            return url
        }
        return nil
    }

    private var resolvedDetailBundleImage: MEPlatformImage? {
        // 1) If productImage is present and not an http URL, try that first
        let prod = model.productImage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prod.isEmpty && !prod.lowercased().starts(with: "http") {
            if let img = loadBundleImage(named: prod) { return img }
        }

        // 2) Try number-based filenames (user-renamed to "MEM042G.png", etc.)
        let trimmedNumber = model.number.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            "\(trimmedNumber).png",
            "\(trimmedNumber).jpg",
            "\(trimmedNumber).jpeg",
            trimmedNumber // asset catalog / name without extension
        ]
        for cand in candidates {
            if let img = loadBundleImage(named: cand) { return img }
        }

        return nil
    }


    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // Header
                VStack(alignment: .center, spacing: 4) {
                    Text(model.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(model.productCode.isEmpty ? "Catalogue ID \(model.number)" : model.productCode)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    // Status label (only shown when status is not blank)
                    if let statusText = model.statusText {
                        Text(statusText)
                            .font(.subheadline)          // matches size of number, adjust if you prefer smaller
                            .fontWeight(.semibold)
                            .foregroundColor(model.statusColor)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal)

                // Hero product image (unchanged behavior)
                // Hero product image (robust resolver)
                if let url = resolvedDetailRemoteURL {
                    // Remote URL via AsyncImage
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 200)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 300)
                                .cornerRadius(8)
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal)
                } else if let platformImage = resolvedDetailBundleImage {
                    // Bundle image (model.number.png/.jpg or productImage treated as bundle name)
                    #if os(iOS)
                    Image(uiImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .cornerRadius(8)
                        .padding(.horizontal)   // apply inside iOS branch
                    #else
                    Image(nsImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .cornerRadius(8)
                        .padding(.horizontal)   // apply inside macOS branch
                    #endif
                } else {
                    // Placeholder
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                }


                // SIDE-BY-SIDE like before: left = checkboxes/qty/favorite, right = details + links
                HStack(alignment: .top, spacing: 20) {
                    // Left column: collector state and quantity
                    VStack(alignment: .leading, spacing: 12) {
                        // Collected toggle (remains free)
                        Button(action: { dataManager.toggleChecked(for: model) }) {
                            HStack(spacing: 8) {
                                Image(systemName: model.checked ? "checkmark.square.fill" : "square")
                                    .frame(width: 24, alignment: .leading)
                                Text(model.checked ? "Collected" : "Uncollected")
                                Spacer()
                            }
                            .foregroundColor(model.checked ? .green : .gray)
                        }
                        .buttonStyle(.plain)

                        // Carded/unboxed state
                        Button(action: {
                            if purchaseManager.isUnlocked {
                                dataManager.toggleBuilt(for: model)
                            } else {
                                showingUnlockSheet = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                if !purchaseManager.isUnlocked {
                                    SubtleLockBadge()
                                        .onTapGesture { showingUnlockSheet = true }
                                } else {
                                    Image(systemName: model.built ? "checkmark.square.fill" : "square")
                                        .frame(width: 24, alignment: .leading)
                                }

                                Text(model.built ? "Unboxed" : "Carded / Not Set")
                                Spacer()
                            }
                            .foregroundColor(model.built ? .blue : .gray)
                        }
                        .buttonStyle(.plain)

                        // Favorite toggle (paid) — lock on the left
                        Button(action: {
                            if purchaseManager.isUnlocked {
                                dataManager.toggleFavorite(for: model)
                            } else {
                                showingUnlockSheet = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                if !purchaseManager.isUnlocked {
                                    SubtleLockBadge()
                                        .onTapGesture { showingUnlockSheet = true }
                                } else {
                                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                                        .frame(width: 24, alignment: .leading)
                                }

                                Text(model.isFavorite ? "Favorite" : "Add to Favorites")
                                Spacer()
                            }
                            .foregroundColor(model.isFavorite ? .yellow : .gray)
                        }
                        .buttonStyle(.plain)

                        // Wishlist toggle (paid) — lock on the left
                        Button(action: {
                            if purchaseManager.isUnlocked {
                                dataManager.toggleWishlist(for: model)
                            } else {
                                showingUnlockSheet = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                if !purchaseManager.isUnlocked {
                                    SubtleLockBadge()
                                        .onTapGesture { showingUnlockSheet = true }
                                } else {
                                    Image(systemName: model.isWishlisted ? "gift.fill" : "gift")
                                        .frame(width: 24, alignment: .leading)
                                }

                                Text(model.isWishlisted ? "Wishlist" : "Add to Wishlist")
                                Spacer()
                            }
                            .foregroundColor(model.isWishlisted ? .pink : .gray)
                        }
                        .buttonStyle(.plain)

                        // Quantity selector (paid) — Menu when unlocked, tappable row when locked
                        if purchaseManager.isUnlocked {
                            Menu {
                                ForEach(1..<11, id: \.self) { quantity in
                                    Button {
                                        dataManager.updateQuantity(for: model, quantity: quantity)
                                    } label: {
                                        if quantity == model.quantity {
                                            Label("Quantity: \(quantity)", systemImage: "checkmark")
                                        } else {
                                            Text("Quantity: \(quantity)")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "number.square")
                                        .frame(width: 24, alignment: .leading)
                                    Text("Qty Owned: \(model.quantity)")
                                    Spacer()
                                }
                                .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Locked presentation for quantity — tapping opens unlock sheet
                            Button {
                                showingUnlockSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    SubtleLockBadge()
                                    Text("Qty Owned: \(model.quantity)")
                                    Spacer()
                                }
                                .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(groupedBG)
                    .cornerRadius(10)
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 200, alignment: .leading)

                    // Right column: catalogue details and source link
                    VStack(alignment: .leading, spacing: 12) {
                        if let year = model.firstReleaseYear {
                            HStack {
                                Image(systemName: "calendar")
                                Text("First released: \(String(year))")
                            }
                        }

                        if model.releaseCount > 0 {
                            HStack {
                                Image(systemName: "square.stack.3d.up")
                                Text("Documented releases: \(model.releaseCount)")
                            }
                        }

                        if !model.category.isEmpty {
                            Label(model.category, systemImage: "film")
                        }

                        if !model.character.isEmpty && model.character != model.name {
                            Label(model.character, systemImage: "person.crop.circle")
                        }

                        if !model.series.isEmpty {
                            Label(model.series, systemImage: "rectangle.stack")
                        }

                        if !model.type.isEmpty {
                            Label(model.type, systemImage: "tag")
                        }

                        if !model.link.isEmpty {
                            Button {
                                openExternalURL(model.link)
                            } label: {
                                HStack {
                                    Image(systemName: "link")
                                    Text("Vehicle Database Source")
                                }
                            }
                        }
                    }

                    .padding()
                    .background(groupedBG)
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // Source-derived catalogue notes
                if !model.modelDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Catalogue Notes")
                            .font(.headline)
                        Text(model.modelDescription)
                            .font(.body)
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
                        if !purchaseManager.isUnlocked {
                            SubtleLockBadge()
                                .onTapGesture { showingUnlockSheet = true }
                        }
                        Text("Photos")
                            .font(.headline)

                        Spacer()

                        #if os(iOS) && !targetEnvironment(macCatalyst)
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
                        #endif
                    }

                    if photos.isEmpty {
                        ZStack {
                            Text("No photos yet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()

                            // Locked overlay CTA when empty
                            if !purchaseManager.isUnlocked {
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
                                                        if purchaseManager.isUnlocked {
                                                            selectedPhotoFromDetail = photo
                                                        } else {
                                                            showingUnlockSheet = true
                                                        }
                                                    }

                                                Button {
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
                                                .disabled(!purchaseManager.isUnlocked)
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
                                                        if purchaseManager.isUnlocked {
                                                            selectedPhotoFromDetail = photo
                                                        } else {
                                                            showingUnlockSheet = true
                                                        }
                                                    }

                                                Button {
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
                                                .disabled(!purchaseManager.isUnlocked)
                                            }
                                        }
                    #endif
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 2)
                            }

                            // Dim overlay + center CTA when locked
                            if !purchaseManager.isUnlocked {
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
                        if !purchaseManager.isUnlocked {
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
                            .onAppear { noteText = note?.text ?? "" }
                            .onChange(of: noteText) { _, newValue in
                                if purchaseManager.isUnlocked {
                                    dataManager.updateNote(for: model, text: newValue)
                                } else {
                                    // revert edits locally (do not save)
                                    noteText = note?.text ?? ""
                                }
                            }
                            .disabled(!purchaseManager.isUnlocked)
                            .opacity(purchaseManager.isUnlocked ? 1.0 : 0.95)

                        // Overlay when locked (identical to Photos style)
                        if !purchaseManager.isUnlocked {
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
        .sheet(item: $selectedPhotoFromDetail) { tappedPhoto in
            ModelDetailPhotoHost(
                model: model,
                tappedPhoto: tappedPhoto,
                dataManager: dataManager,
                parentSelectedPhoto: $selectedPhotoFromDetail
            )
        }

                // Titles by platform (keeps iPhone inline title)
                #if os(iOS) || targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
                #else
                .navigationTitle(model.name)
                #endif

                // iPhone camera sheet
                #if os(iOS) && !targetEnvironment(macCatalyst)
                .sheet(isPresented: $showImagePicker, onDismiss: loadImage) {
                    ImagePicker(image: $inputImage, sourceType: imagePickerSource)
                }
                #endif

                // Mac/Catalyst PhotosPicker handler
                #if (os(macOS) || targetEnvironment(macCatalyst)) && canImport(PhotosUI)
                .onChange(of: photoItem) { _, newItem in
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
        guard let inputImage,
              let data = inputImage.jpegData(compressionQuality: 0.8) else { return }
        dataManager.addPhoto(for: model, imageData: data)
        self.inputImage = nil
    }
    #endif
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
        let modelPhotos = dataManager.allPhotos
            .filter { $0.modelId == model.id }
            .sorted { $0.timestamp > $1.timestamp }

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
            let modelPhotos = dataManager.allPhotos
                .filter { $0.modelId == model.id }
                .sorted { $0.timestamp > $1.timestamp }
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

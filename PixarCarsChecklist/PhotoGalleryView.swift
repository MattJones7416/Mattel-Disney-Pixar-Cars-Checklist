import SwiftUI
import SwiftData

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

/// Cross-platform cache for decoded images.
private final class ImageCache {
    static let shared = ImageCache()
    private init() {}
    #if os(iOS) || targetEnvironment(macCatalyst)
    private let cache = NSCache<NSData, UIImage>()
    #else
    private let cache = NSCache<NSData, NSImage>()
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
    func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
    #else
    func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
    #endif
}

struct PhotoGalleryView: View {
    @ObservedObject var dataManager: DataManager
    @Binding var selectedTab: ContentView.Tab
    @Binding var selectedModel: MetalModel?

    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingUnlockSheet = false

    @State private var selectedPhoto: ModelPhoto?

    private var modelsWithPhotos: [MetalModel] {
        dataManager.allModels.filter { !dataManager.getPhotos(for: $0).isEmpty }
    }

    private let grid = [GridItem(.adaptive(minimum: 120), spacing: 2)]

    private var allPhotosWithModels: [(photo: ModelPhoto, model: MetalModel)] {
        modelsWithPhotos.flatMap { model in
            dataManager.getPhotos(for: model).map { (photo: $0, model: model) }
        }
    }

    struct PhotoGridItemView: View {
        let photo: ModelPhoto
        let model: MetalModel
        let onTap: () -> Void

        var body: some View {
            ZStack(alignment: .bottomLeading) {
#if os(iOS) || targetEnvironment(macCatalyst)
                if let uiImage = ImageCache.shared.image(for: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipped()
                } else {
                    Color.gray.frame(width: 120, height: 120)
                }
#else
                if let nsImage = ImageCache.shared.image(for: photo.imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipped()
                } else {
                    Color.gray.frame(width: 120, height: 120)
                }
#endif

                Text(model.name)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            .frame(width: 120, height: 120)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: grid, spacing: 2) {
                    ForEach(allPhotosWithModels, id: \.photo.id) { pair in
                        PhotoGridItemView(photo: pair.photo, model: pair.model) {
                            if purchaseManager.isUnlocked {
                                selectedPhoto = pair.photo
                            } else {
                                showingUnlockSheet = true
                            }
                        }
                        .overlay(
                            Group {
                                if !purchaseManager.isUnlocked {
                                    // dim + lock badge
                                    Color.black.opacity(0.12)
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: "lock")
                                                .font(.caption2)
                                                .foregroundColor(Color.gray.opacity(0.8))
                                                .padding(6)
                                                .background(Color(.systemGray5))
                                                .clipShape(Circle())
                                                .padding(6)
                                                .offset(x: 40, y: -40)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(8)
            }

            // if unlocked, selectedPhoto sheet behavior is unchanged below
        }
        .sheet(isPresented: $showingUnlockSheet) {
            UnlockSheet().environmentObject(purchaseManager)
        }

        // present detail viewer (unchanged when unlocked)
    #if os(iOS) && !targetEnvironment(macCatalyst)
        .fullScreenCover(item: $selectedPhoto) { tappedPhoto in
            if let model = dataManager.allModels.first(where: { $0.id == tappedPhoto.modelId }) {
                let modelPhotos = dataManager.getPhotos(for: model)
                let startIndex = modelPhotos.firstIndex { $0.id == tappedPhoto.id } ?? 0

                PhotoDetailViewWrapper(
                    model: model,
                    initialPhotos: modelPhotos,
                    startIndex: startIndex,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    selectedTab: $selectedTab,
                    isPresented: Binding(
                        get: { selectedPhoto != nil },
                        set: { if !$0 { selectedPhoto = nil } }
                    )
                )
            }
        }
    #else
        .sheet(item: $selectedPhoto) { tappedPhoto in
            if let model = dataManager.allModels.first(where: { $0.id == tappedPhoto.modelId }) {
                let modelPhotos = dataManager.getPhotos(for: model)
                let startIndex = modelPhotos.firstIndex { $0.id == tappedPhoto.id } ?? 0

                PhotoDetailViewWrapper(
                    model: model,
                    initialPhotos: modelPhotos,
                    startIndex: startIndex,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    selectedTab: $selectedTab,
                    isPresented: Binding(
                        get: { selectedPhoto != nil },
                        set: { if !$0 { selectedPhoto = nil } }
                    )
                )
                .frame(minWidth: 900, minHeight: 650)
            }
        }
    #endif
    }
}

// Helper wrapper to manage state properly
struct PhotoDetailViewWrapper: View {
    let model: MetalModel
    let initialPhotos: [ModelPhoto]
    let startIndex: Int
    let dataManager: DataManager
    @Binding var selectedModel: MetalModel?
    @Binding var selectedTab: ContentView.Tab
    @Binding var isPresented: Bool

    @State private var currentIndex: Int
    @State private var photos: [ModelPhoto]

    init(model: MetalModel, initialPhotos: [ModelPhoto], startIndex: Int, dataManager: DataManager, selectedModel: Binding<MetalModel?>, selectedTab: Binding<ContentView.Tab>, isPresented: Binding<Bool>) {
        self.model = model
        self.initialPhotos = initialPhotos
        self.startIndex = startIndex
        self.dataManager = dataManager
        self._selectedModel = selectedModel
        self._selectedTab = selectedTab
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: startIndex)
        self._photos = State(initialValue: initialPhotos)
    }

    var body: some View {
        PhotoDetailView(
            model: model,
            photos: $photos,
            currentIndex: $currentIndex,
            dataManager: dataManager,
            onClose: {
                isPresented = false
            },
            onOpenModel: {
                selectedTab = .list
                selectedModel = model
                isPresented = false
            },
            showsModelControls: true
        )
    }
}

struct PhotoDetailView: View {
    @ObservedObject var dataManager: DataManager
    let model: MetalModel

    @Binding var photos: [ModelPhoto]
    @Binding var currentIndex: Int
    let onClose: () -> Void
    let onOpenModel: () -> Void
    let showsModelControls: Bool

    @State private var showDeleteAlert = false

    // Add this convenience initializer for ModelDetailView usage
    init(
        model: MetalModel,
        photos: Binding<[ModelPhoto]>,
        currentIndex: Binding<Int>,
        dataManager: DataManager,
        onClose: @escaping () -> Void,
        onOpenModel: @escaping () -> Void,
        showsModelControls: Bool = true
    ) {
        self.model = model
        self._photos = photos
        self._currentIndex = currentIndex
        self.dataManager = dataManager
        self.onClose = onClose
        self.onOpenModel = onOpenModel
        self.showsModelControls = showsModelControls
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
#if os(iOS) || targetEnvironment(macCatalyst)
                    if let uiImage = ImageCache.shared.image(for: photo.imageData) {
                        ZoomableImageView(image: uiImage)
                            .id(photo.id)
                            .tag(index)
                    } else {
                        Color.clear.tag(index)
                    }
#else
                    if let nsImage = ImageCache.shared.image(for: photo.imageData) {
                        ZoomableImageView(image: nsImage)
                            .id(photo.id)
                            .tag(index)
                    } else {
                        Color.clear.tag(index)
                    }
#endif
                }
            }
#if os(iOS) || targetEnvironment(macCatalyst)
    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
#else
    .tabViewStyle(.automatic)
#endif

            // Top bar
            VStack {
                HStack {
                    Button {
                        DispatchQueue.main.async { onClose() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                    .contentShape(Rectangle())
                    .zIndex(3)
                    .buttonStyle(.plain)

                    Spacer()

                    if !photos.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                        .contentShape(Rectangle())
                        .zIndex(3)
                        .buttonStyle(.plain)
                        .alert("Delete this photo?", isPresented: $showDeleteAlert) {
                            Button("Delete", role: .destructive) { deleteCurrent() }
                            Button("Cancel", role: .cancel) {
                                // clear the alert
                                showDeleteAlert = false

                                // Re-sync photos from dataManager in case any external/store-side change
                                // or transient UI state left the view in an inconsistent state.
                                let refreshed = dataManager.getPhotos(for: model)
                                photos = refreshed

                                // Clamp currentIndex safely and force small UI update
                                if photos.isEmpty {
                                    // if there are no photos after refresh, dismiss safely on main thread
                                    DispatchQueue.main.async {
                                        onClose()
                                    }
                                } else if currentIndex >= photos.count {
                                    currentIndex = max(0, photos.count - 1)
                                } else {
                                    // nudge SwiftUI to re-evaluate child views (helps clear stale gestures)
                                    DispatchQueue.main.async {
                                        currentIndex = currentIndex
                                    }
                                    NotificationCenter.default.post(name: .init("RefreshPhotosForModel_\(model.id)"), object: nil)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .padding(.top, 24)
                #else
                .padding(.top, 8)
                #endif

                Spacer()
            }
            .zIndex(4) // push top area above everything else

            // Bottom bar
            VStack {
                Spacer()
                HStack {
                    Text("\(currentIndex + 1) of \(photos.count)")
                        .foregroundStyle(.white)
                        .font(.subheadline)

                    Spacer()

                 //   Text(model.name)
                 //       .foregroundStyle(.white)
                //        .font(.subheadline)
                //        .lineLimit(1)

                    Spacer()

                    if showsModelControls {
                        Button(action: onOpenModel) {
                            Label("Open Model", systemImage: "cube.transparent")
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
#if os(macOS) || targetEnvironment(macCatalyst)
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal)
#if os(macOS) || targetEnvironment(macCatalyst)
                .padding(.bottom, 24)
#else
                .padding(.bottom, 12)
#endif
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if newValue >= photos.count && !photos.isEmpty {
                currentIndex = max(0, photos.count - 1)
            }
        }
    }

    private func deleteCurrent() {
        guard !photos.isEmpty, currentIndex < photos.count else { return }
        let photo = photos[currentIndex]
        dataManager.deletePhoto(photo)
        photos.remove(at: currentIndex)

        if photos.isEmpty {
            onClose()
        } else if currentIndex >= photos.count {
            currentIndex = max(0, photos.count - 1)
        }
    }
} // Closing brace that was missing

struct ZoomableImageView: View {
#if os(iOS) || targetEnvironment(macCatalyst)
    let image: UIImage
#else
    let image: NSImage
#endif

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
#if os(iOS) || targetEnvironment(macCatalyst)
        let swiftUIImage = Image(uiImage: image)
#else
        let swiftUIImage = Image(nsImage: image)
#endif

        let isZoomed = scale > 1.01

        swiftUIImage
            .resizable()
            .scaledToFit()
            .offset(offset)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value
                        scale = min(max(newScale, 1.0), 4.0)
                    }
                    .onEnded { _ in
                        lastScale = max(1.0, min(scale, 4.0))
                        if scale <= 1.0 { withAnimation { offset = .zero } }
                    }
            )
            .overlay(
                Group {
                    if scale > 1.01 {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let delta = CGSize(
                                            width: value.translation.width - lastOffset.width,
                                            height: value.translation.height - lastOffset.height
                                        )
                                        offset = CGSize(
                                            width: offset.width + delta.width,
                                            height: offset.height + delta.height
                                        )
                                        lastOffset = value.translation
                                    }
                                    .onEnded { _ in
                                        lastOffset = .zero
                                        if scale <= 1.0 { withAnimation { offset = .zero } }
                                    }
                            )
                            .allowsHitTesting(true)
                    } else {
                        // transparent, but does not catch taps
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)
                    }
                }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut) {
                    if isZoomed {
                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.0; lastScale = 2.0
                    }
                }
            }
            .background(Color.black)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

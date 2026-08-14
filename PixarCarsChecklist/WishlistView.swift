import SwiftUI
import UniformTypeIdentifiers

struct WishlistView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedTab: ContentView.Tab
    @Binding var selectedModel: MetalModel?
    var sourceModels: [MetalModel]?
    var readOnly: Bool = false
    var onCollectionChanged: () -> Void = {}

    @State private var showingEmptyAlert = false
    @State private var isExporting = false
    @State private var showingFileExporter = false
    @State private var exportDocument: DataDocument?

    private var models: [MetalModel] {
        sourceModels ?? dataManager.wishlistedModels
    }

    var body: some View {
        ModelBrowserView(
            title: "Wishlist",
            sourceModels: models,
            emptyTitle: "No items in your wishlist",
            emptySubtitle: "Tap the gift icon on a model to add it here.",
            storagePrefix: "wishlist",
            selectedModel: $selectedModel,
            trailingAction: readOnly ? nil : AnyView(shareButton),
            readOnly: readOnly,
            onCollectionChanged: onCollectionChanged
        )
        .environmentObject(dataManager)
        .alert("Nothing to share", isPresented: $showingEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your wishlist is empty. Add items before sharing.")
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .html,
            defaultFilename: "Pixar Cars Wishlist.html"
        ) { result in
            if case .failure(let error) = result {
                print("Export failed:", error)
            }
            exportDocument = nil
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !dataManager.wishlistedModels.isEmpty {
            #if os(macOS) && !targetEnvironment(macCatalyst)
            ShareButtonMac {
                makeWishlistHTMLFile()
            }
            #else
            Button {
                exportWishlistHTML()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)
            #endif
        }
    }

    private func exportWishlistHTML() {
        guard !isExporting else { return }
        let html = dataManager.generateWishlistShareHTML()
        guard !html.isEmpty, let data = html.data(using: .utf8) else {
            showingEmptyAlert = true
            return
        }

        isExporting = true
        exportDocument = DataDocument(data: data)
        showingFileExporter = true
        isExporting = false
    }

    private func makeWishlistHTMLFile() -> URL? {
        let html = dataManager.generateWishlistShareHTML()
        guard !html.isEmpty, let data = html.data(using: .utf8) else {
            showingEmptyAlert = true
            return nil
        }

        do {
            let caches = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let file = caches.appendingPathComponent("Metal-Model-Wishlist-\(UUID().uuidString).html")
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            print("Failed to write wishlist HTML:", error)
            return nil
        }
    }
}

#Preview {
    WishlistView(selectedTab: .constant(.list), selectedModel: .constant(nil))
        .environmentObject(DataManager.shared)
}

struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html, .data] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

struct ShareButtonMac: View {
    var makeURL: () -> URL?
    @State private var anchor: NSView?

    var body: some View {
        Button {
            guard let url = makeURL(), let view = anchor else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .background(AnchorView(view: $anchor))
    }
}

private struct AnchorView: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { view = nsView }
}
#endif

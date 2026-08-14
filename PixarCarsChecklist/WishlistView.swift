import SwiftUI

struct WishlistView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedTab: ContentView.Tab
    @Binding var selectedModel: MetalModel?
    @State private var searchText: String = ""
    @State private var shareText: String = ""
    @State private var showingShare: Bool = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var exportDataDocument: DataDocument?
    @State private var showingEmptyAlert = false
    @State private var isExporting = false
    @State private var showingFileExporter = false
    @State private var exportDocument: DataDocument? = nil
    #if os(macOS) && !targetEnvironment(macCatalyst)
    @State private var shareAnchorRect: CGRect = .zero
    #endif

    private var filtered: [MetalModel] {
        dataManager.getWishlistedModels(searchText: searchText)
            .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }

    private func wishlistPlainText() -> String {
        let models = filtered
        guard !models.isEmpty else { return "" }
        let lines: [String] = models.map { model in
            let number = model.productCode.isEmpty ? model.number : model.productCode
            let name = model.name
            let link = model.link
            return "\(number)\t\(name)\t\(link)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wishlist")
                    .font(.title2.bold())
                Spacer()
                if !filtered.isEmpty {
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    Button {
                        guard !isExporting else { return }
                        let text = dataManager.generateWishlistShareText()
                        guard !text.isEmpty else { showingEmptyAlert = true; return }
                        isExporting = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            let plain = wishlistPlainText()
                            let data = plain.data(using: .utf8)
                            DispatchQueue.main.async {
                                if let data = data, !plain.isEmpty {
                                    self.exportDocument = DataDocument(data: data)
                                    self.showingFileExporter = true
                                } else {
                                    self.exportDocument = nil
                                    self.showingEmptyAlert = true
                                }
                                self.isExporting = false
                            }
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                    #else
                    // macOS: Use NSSharingServicePicker for a native share menu
                    ShareButtonMac {
                        let text = dataManager.generateWishlistShareText()
                        guard !text.isEmpty else { showingEmptyAlert = true; return nil }
                        if let pdfData = makeWishlistPDF(from: text, title: "Wishlist") {
                            do {
                                let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                                let file = caches.appendingPathComponent("Wishlist-\(UUID().uuidString).pdf")
                                try pdfData.write(to: file, options: .atomic)
                                return file
                            } catch {
                                print("Failed to write PDF:", error)
                                return nil
                            }
                        }
                        return nil
                    }
                    #endif
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search wishlist...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No items in your wishlist")
                        .foregroundColor(.secondary)
                    Text("Tap the gift icon on a car to add it here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, id: \.id) { model in
                    Button {
                        selectedTab = .list
                        selectedModel = model
                    } label: {
                        ModelRowView(
                            model: model,
                            accentColor: Color(hex: "D92D20"),
                            compact: false,
                            dataManager: dataManager
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(
                        model.checked ? Color(hex: "D92D20").opacity(0.1) : Color.clear
                    )
                }
                .listStyle(.plain)
            }
        }
        .alert("Nothing to share", isPresented: $showingEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your wishlist is empty. Add items before sharing.")
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "Wishlist.txt"
        ) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                print("Export failed:", error)
            }
            // Reset document after export/share attempt
            exportDocument = nil
        }
    }
}

#Preview {
    WishlistView(selectedTab: .constant(.list), selectedModel: .constant(nil))
        .environmentObject(DataManager.shared)
}

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
private func makeWishlistPDF(from text: String, title: String) -> Data? {
    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
    let data = renderer.pdfData { ctx in
        ctx.beginPage()
        let margin: CGFloat = 32
        let drawRect = pageRect.insetBy(dx: margin, dy: margin)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18)
        ]
        let titleHeight = (title as NSString).boundingRect(
            with: CGSize(width: drawRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttrs,
            context: nil
        ).height
        (title as NSString).draw(in: CGRect(x: drawRect.minX,
                                            y: drawRect.minY,
                                            width: drawRect.width,
                                            height: titleHeight),
                                 withAttributes: titleAttrs)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraph
        ]

        let bodyRect = CGRect(
            x: drawRect.minX,
            y: drawRect.minY + titleHeight + 12,
            width: drawRect.width,
            height: drawRect.height - titleHeight - 12
        )
        (text as NSString).draw(in: bodyRect, withAttributes: attrs)
    }
    return data
}
#endif

#if os(iOS) || targetEnvironment(macCatalyst)
// Removed ActivityViewController (not needed after changes)
#endif

import UniformTypeIdentifiers
struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
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
            guard let url = makeURL() else { return }
            if let view = anchor {
                let picker = NSSharingServicePicker(items: [url])
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
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

import SwiftUI

struct ModelBrowserView: View {
    @EnvironmentObject var dataManager: DataManager

    let title: String
    let sourceModels: [MetalModel]
    let emptyTitle: String
    let emptySubtitle: String
    let trailingAction: AnyView?
    let readOnly: Bool
    let onCollectionChanged: () -> Void
    @Binding var selectedModel: MetalModel?

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = Debouncer(delay: 0.3)
    @State private var hiddenCategories: Set<String> = []
    @State private var expandedCategories: Set<String> = []
    @State private var showingFilters = false

    @AppStorage private var showCollected: Bool
    @AppStorage private var showUncollected: Bool
    @AppStorage private var showBuilt: Bool
    @AppStorage private var showUnbuilt: Bool
    @AppStorage private var showComingSoon: Bool
    @AppStorage private var showExclusive: Bool
    @AppStorage private var showRetired: Bool
    @AppStorage private var showNormal: Bool
    @AppStorage private var sortOption: String
    @AppStorage private var sortAscending: Bool
    @AppStorage private var viewMode: String
    @AppStorage private var selectedType: String
    @AppStorage private var showImageGrid: Bool

    private let accentColor = Color(hex: "D92D20")

    private var allTypes: [String] {
        let preferred = ["1:55 Die-Cast", "Mini Racers", "Collector Exclusive", "Special Edition", "Premium / Larger Scale"]
        let available = Set(sourceModels.map { normalizedModelType($0) })
        let ordered = preferred.filter { available.contains($0) }
        let remaining = available.subtracting(ordered).sorted()
        return ["All"] + ordered + remaining
    }

    init(
        title: String,
        sourceModels: [MetalModel],
        emptyTitle: String,
        emptySubtitle: String,
        storagePrefix: String,
        selectedModel: Binding<MetalModel?>,
        trailingAction: AnyView? = nil,
        readOnly: Bool = false,
        onCollectionChanged: @escaping () -> Void = {}
    ) {
        self.title = title
        self.sourceModels = sourceModels
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.trailingAction = trailingAction
        self.readOnly = readOnly
        self.onCollectionChanged = onCollectionChanged
        self._selectedModel = selectedModel

        _showCollected = AppStorage(wrappedValue: true, "\(storagePrefix).showCollected")
        _showUncollected = AppStorage(wrappedValue: true, "\(storagePrefix).showUncollected")
        _showBuilt = AppStorage(wrappedValue: true, "\(storagePrefix).showBuilt")
        _showUnbuilt = AppStorage(wrappedValue: true, "\(storagePrefix).showUnbuilt")
        _showComingSoon = AppStorage(wrappedValue: true, "\(storagePrefix).showComingSoon")
        _showExclusive = AppStorage(wrappedValue: true, "\(storagePrefix).showExclusive")
        _showRetired = AppStorage(wrappedValue: true, "\(storagePrefix).showRetired")
        _showNormal = AppStorage(wrappedValue: true, "\(storagePrefix).showNormal")
        _sortOption = AppStorage(wrappedValue: "name", "\(storagePrefix).sortOption")
        _sortAscending = AppStorage(wrappedValue: true, "\(storagePrefix).sortAscending")
        _viewMode = AppStorage(wrappedValue: "categories", "\(storagePrefix).viewMode")
        _selectedType = AppStorage(wrappedValue: "All", "\(storagePrefix).selectedType")
        _showImageGrid = AppStorage(wrappedValue: false, "\(storagePrefix).showImageGrid")
    }

    private var typeScopedCategories: [String] {
        makeTypeScopedCategories(
            from: sourceModels,
            selectedType: selectedType
        )
    }

    private var filteredModels: [MetalModel] {
        filteredModels(using: debouncedSearchText)
    }

    private func filteredModels(using searchValue: String) -> [MetalModel] {
        var result = typeFiltered(sourceModels, includeCategoryVisibility: true)

        if !searchValue.isEmpty {
            result = result.filter { $0.matches(searchValue) }
        }

        if !showCollected {
            result = result.filter { !$0.checked }
        }
        if !showUncollected {
            result = result.filter { $0.checked }
        }
        if !showBuilt {
            result = result.filter { !$0.built }
        }
        if !showUnbuilt {
            result = result.filter { $0.built }
        }

        result = result.filter { model in
            let status = model.status
            return
                (showComingSoon && status == "Coming Soon") ||
                (showExclusive && status == "Exclusive") ||
                (showRetired && status == "Retired") ||
                (showNormal && !["Coming Soon", "Exclusive", "Retired"].contains(status))
        }

        return sortMetalModels(result, by: sortOption, ascending: sortAscending)
    }

    private var categorizedModels: [String: [MetalModel]] {
        categorizedModels(for: filteredModels)
    }

    private func categorizedModels(for models: [MetalModel]) -> [String: [MetalModel]] {
        Dictionary(grouping: models, by: { $0.category })
    }

    private var collectionStats: (collected: Int, total: Int) {
        collectionStats(for: filteredModels)
    }

    private func collectionStats(for models: [MetalModel]) -> (collected: Int, total: Int) {
        (models.filter { $0.checked }.count, models.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            let visibleSnapshot = makeVisibleModelSnapshot(
                from: sourceModels,
                selectedType: selectedType,
                searchText: debouncedSearchText,
                hiddenCategories: hiddenCategories,
                showCollected: showCollected,
                showUncollected: showUncollected,
                showBuilt: showBuilt,
                showUnbuilt: showUnbuilt,
                showComingSoon: showComingSoon,
                showExclusive: showExclusive,
                showRetired: showRetired,
                showNormal: showNormal,
                sortOption: sortOption,
                sortAscending: sortAscending,
                includeExtendedSearch: true
            )
            let visibleModels = visibleSnapshot.models
            let visibleCategorySet = visibleSnapshot.categorySet
            let gridPrefetchKey = [
                showImageGrid.description,
                viewMode,
                visibleSnapshot.prefetchSignature
            ].joined(separator: "|")

            HStack {
                Text(title)
                    .font(.title2.bold())
                Spacer()
                if let trailingAction {
                    trailingAction
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            SearchBar(text: $searchText)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: searchText) { _, newValue in
                    searchDebouncer.run {
                        debouncedSearchText = newValue
                        if !newValue.isEmpty {
                            let matchingSnapshot = makeVisibleModelSnapshot(
                                from: sourceModels,
                                selectedType: selectedType,
                                searchText: newValue,
                                hiddenCategories: hiddenCategories,
                                showCollected: showCollected,
                                showUncollected: showUncollected,
                                showBuilt: showBuilt,
                                showUnbuilt: showUnbuilt,
                                showComingSoon: showComingSoon,
                                showExclusive: showExclusive,
                                showRetired: showRetired,
                                showNormal: showNormal,
                                sortOption: sortOption,
                                sortAscending: sortAscending,
                                includeExtendedSearch: true
                            )
                            expandedCategories.formUnion(matchingSnapshot.sortedCategories)
                        }
                    }
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allTypes, id: \.self) { type in
                        Button(action: { selectedType = type }) {
                            Text(type)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedType == type ? accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                                .foregroundColor(selectedType == type ? accentColor : .primary)
                                .cornerRadius(16)
                        }
                        #if os(macOS) || targetEnvironment(macCatalyst)
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
            VStack(spacing: 10) {
                CollectionStatsView(
                    collected: visibleSnapshot.collected,
                    total: visibleSnapshot.total,
                    accentColor: accentColor
                )
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Button {
                        showingFilters.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
                        CatalogFilterPopover(
                            showCollected: $showCollected,
                            showUncollected: $showUncollected,
                            showBuilt: $showBuilt,
                            showUnbuilt: $showUnbuilt,
                            showComingSoon: $showComingSoon,
                            showExclusive: $showExclusive,
                            showRetired: $showRetired,
                            showNormal: $showNormal,
                            hiddenCategories: $hiddenCategories,
                            categories: typeScopedCategories
                        )
                    }
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    .buttonStyle(.plain)
                    #endif

                    if viewMode == "categories" {
                        Button(action: { toggleVisibleCategories(visibleCategorySet) }) {
                            let allVisibleExpanded = !visibleCategorySet.isEmpty && expandedCategories.intersection(visibleCategorySet).count == visibleCategorySet.count
                            Image(systemName: allVisibleExpanded ? "arrow.up.to.line" : "arrow.down.to.line")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        #if os(macOS) || targetEnvironment(macCatalyst)
                        .buttonStyle(.plain)
                        #endif
                    }

                    CatalogSortControl(sortOption: $sortOption, sortAscending: $sortAscending)

                    Button(action: { showImageGrid.toggle() }) {
                        Label(showImageGrid ? "List" : "Image",
                              systemImage: showImageGrid ? "list.bullet" : "rectangle.grid.2x2")
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    .buttonStyle(.plain)
                    #endif

                    Button(action: {
                        viewMode = viewMode == "categories" ? "list" : "categories"
                    }) {
                        Label(viewMode == "categories" ? "Unsorted" : "Sorted",
                              systemImage: viewMode == "categories" ? "list.bullet" : "rectangle.grid.1x2")
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    .buttonStyle(.plain)
                    #endif
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            content(snapshot: visibleSnapshot)
                .task(id: gridPrefetchKey) {
                    guard showImageGrid else { return }
                    let prefetchModels = Array(visibleModels.prefix(120))
                    MEBundleImagePrefetcher.shared.prefetch(
                        candidatesList: prefetchModels.map { bundleImageCandidates(for: $0) }
                    )
                    MERemoteImagePrefetcher.shared.prefetch(
                        urlStrings: prefetchModels.compactMap { remoteImageURLString(for: $0) }
                    )
                }
        }
    }

    @ViewBuilder
    private func content(snapshot: VisibleModelSnapshot) -> some View {
        if snapshot.models.isEmpty {
            VStack(spacing: 8) {
                Text(sourceModels.isEmpty ? emptyTitle : "No matching models")
                    .foregroundColor(.secondary)
                Text(sourceModels.isEmpty ? emptySubtitle : "Adjust search or filters to show more models.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewMode == "categories" {
            if showImageGrid {
                CategoryGridView(
                    categorizedModels: snapshot.categorizedModels,
                    sortedCategories: snapshot.sortedCategories,
                    completeCategories: snapshot.completeCategories,
                    expandedCategories: $expandedCategories,
                    accentColor: accentColor,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    readOnly: readOnly,
                    onCollectionChanged: onCollectionChanged
                )
            } else {
                CategoryListView(
                    categorizedModels: snapshot.categorizedModels,
                    sortedCategories: snapshot.sortedCategories,
                    completeCategories: snapshot.completeCategories,
                    expandedCategories: $expandedCategories,
                    accentColor: accentColor,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    readOnly: readOnly,
                    onCollectionChanged: onCollectionChanged
                )
            }
        } else {
            if showImageGrid {
                PlainGridView(
                    models: snapshot.models,
                    accentColor: accentColor,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    readOnly: readOnly,
                    onCollectionChanged: onCollectionChanged
                )
            } else {
                PlainListView(
                    models: snapshot.models,
                    accentColor: accentColor,
                    dataManager: dataManager,
                    selectedModel: $selectedModel,
                    readOnly: readOnly,
                    onCollectionChanged: onCollectionChanged
                )
            }
        }
    }

    private func typeFiltered(_ models: [MetalModel], includeCategoryVisibility: Bool) -> [MetalModel] {
        var result = models

        if selectedType != "All" {
            result = result.filter { normalizedModelType($0) == selectedType }
        }

        if includeCategoryVisibility && !hiddenCategories.isEmpty {
            result = result.filter { !hiddenCategories.contains($0.category) }
        }

        return result
    }

    private func toggleVisibleCategories(_ visibleSet: Set<String>) {
        let expandedVisibleCount = expandedCategories.intersection(visibleSet).count

        withAnimation {
            if expandedVisibleCount == visibleSet.count {
                expandedCategories.subtract(visibleSet)
            } else {
                expandedCategories.formUnion(visibleSet)
            }
        }
    }
}

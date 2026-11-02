import SwiftUI

private enum LibrarySection: Hashable { case history, reviews, tvProgress }

struct LibraryView: View {
    let detailModel: (MediaDestination, MediaSearchResult?) -> MediaDetailModel
    let openSearch: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(LibraryStore.self) private var library
    @Bindable var organization: LibraryOrganizationModel
    @State private var presentedSection: LibrarySection?
    @State private var errorMessage: String?

    var body: some View {
        List {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-search") {
                Text("UI test data").font(.caption).accessibilityIdentifier("library.testData")
            }
            #endif
            Section("Organize") {
                if textSize.isAccessibilitySize {
                    mediaPicker.pickerStyle(.menu)
                } else { mediaPicker.pickerStyle(.segmented) }
                Picker("Viewing status", selection: $organization.options.status) {
                    ForEach(LibraryStatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("library.statusFilter")
                Toggle("Favorites only", isOn: $organization.options.favoritesOnly).accessibilityIdentifier("library.favoritesFilter")
                Picker("Sort", selection: $organization.options.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("library.sort")
                if organization.hasFilters { Button("Reset Filters") { organization.resetFilters() }.accessibilityIdentifier("library.resetFilters") }
            }
            if let error = library.loadError {
                Text(error.localizedDescription).accessibilityIdentifier("library.loadError")
                Button("Retry Library") { library.reload() }
            }
            Section("Saved titles — \(organization.visible.count) of \(organization.totalCount)") {
                if !organization.sourceReady {
                    ProgressView("Loading saved titles…")
                } else if organization.visible.isEmpty && library.loadError == nil {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                        Text(organization.emptyState.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(organization.emptyState.message)
                        Button("Find Movies and TV", action: openSearch).accessibilityIdentifier("library.findTitles")
                        if organization.hasFilters { Button("Reset Filters") { organization.resetFilters() } }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(organization.totalCount == 0 ? "library.empty" : "library.noMatches")
                }
                ForEach(organization.visible) { item in
                    if let id = item.mediaID {
                        NavigationLink(value: MediaDestination(id: id, title: item.title, year: item.year)) { LibraryRow(item: item) }
                            .accessibilityIdentifier("library.row.\(id.kind.rawValue).\(id.value)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    do { try library.setFavorite(!item.isFavorite, for: id) }
                                    catch { errorMessage = error.localizedDescription }
                                } label: { Label(item.isFavorite ? "Remove Favorite" : "Add Favorite", systemImage: item.isFavorite ? "heart.slash" : "heart") }
                            }
                            .contextMenu {
                                Button(item.isFavorite ? "Remove Favorite" : "Add Favorite") {
                                    do { try library.setFavorite(!item.isFavorite, for: id) }
                                    catch { errorMessage = error.localizedDescription }
                                }
                            }
                    } else { LibraryRow(item: item) }
                }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("TV Episode Progress") { presentedSection = .tvProgress }.accessibilityIdentifier("tv.savedProgress")
                    Button("Viewing History") { presentedSection = .history }.accessibilityIdentifier("diary.open")
                    Button("Personal Reviews") { presentedSection = .reviews }.accessibilityIdentifier("review.archive")
                } label: { Label("More in Library", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("library.more")
            }
        }
        .navigationDestination(item: $presentedSection) { section in
            switch section {
            case .history: ViewingHistoryView()
            case .reviews: PersonalReviewsView()
            case .tvProgress: SavedTVProgressView()
            }
        }
        .searchable(text: $organization.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search saved titles")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: library.revision, initial: true) { _, revision in organization.replaceEntries(library.entries, revision: revision) }
        .modifier(SavedMediaNavigation(detailModel: detailModel))
        .alert("Favorite could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
    private var mediaPicker: some View {
        Picker("Media type", selection: $organization.options.media) {
            ForEach(LibraryMediaFilter.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("library.mediaFilter")
    }

}

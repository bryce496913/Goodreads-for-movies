import SwiftUI

struct SearchView: View {
    @Bindable var model: SearchModel
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        List {
            Section {
                if textSize.isAccessibilitySize { mediaPicker.pickerStyle(.menu) }
                else { mediaPicker.pickerStyle(.segmented) }
            }
            if model.usesTestData {
                Text("UI test data").font(.caption).accessibilityIdentifier("search.testData")
            }
            switch model.phase {
            case .idle:
                EmptyStateCard(title: "Find your next story", systemImage: "magnifyingglass",
                               message: "Search for movies and TV shows.", presentation: .inline)
            case .loading:
                AppLoadingState(title: "Searching…").accessibilityIdentifier("search.loading")
            case .cancelled:
                Text("Search canceled. Try again when you are ready.")
                Button("Retry Search") { model.retry() }.buttonStyle(AppActionStyle()).accessibilityIdentifier("search.retry")
            case .failed(let error):
                Section {
                    EmptyStateCard(title: "Search unavailable", systemImage: "exclamationmark.triangle",
                                   message: error.localizedDescription, presentation: .inline)
                        .accessibilityIdentifier("search.error")
                    Button("Retry Search") { model.retry() }.buttonStyle(AppActionStyle()).accessibilityIdentifier("search.retry")
                }
            case .loaded:
                if model.items.isEmpty {
                    EmptyStateCard(title: "No results", systemImage: "magnifyingglass",
                        message: model.nextPage == nil
                            ? "Try another title or media filter."
                            : "No matching titles on this page. More pages are available below.", presentation: .inline)
                        .accessibilityIdentifier("search.empty")
                }
                ForEach(model.items) { item in
                    NavigationLink(value: item.destination) {
                        SearchResultRow(item: item, posterURL: model.imageResolver?.posterURL(reference: item.posterReference))
                    }
                    .accessibilityIdentifier("search.result.\(item.id.kind.rawValue).\(item.id.value)")
                }
                pagination
                if model.artworkUnavailable {
                    Section {
                        Text("Artwork is unavailable. Titles are still available.").font(.footnote)
                        Button("Retry Artwork") { model.retryArtwork() }
                    }
                }
                if !model.usesTestData && !model.items.isEmpty {
                    Section {
                        if let attributionURL = URL(string: "https://www.themoviedb.org") {
                            Link("Data provided by TMDB", destination: attributionURL)
                        }
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appListScreen(AppTab.search.title, isRoot: true)
        .accessibilityIdentifier("screen.search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movies and TV shows")
        .autocorrectionDisabled()
        .navigationDestination(for: MediaDestination.self) { MediaDetailView(model: model.detailModel(for: $0)) }
    }

    private var mediaPicker: some View {
        Picker("Media type", selection: $model.filter) {
            ForEach(SearchFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
        }.accessibilityIdentifier("search.filters")
    }

    @ViewBuilder
    private var pagination: some View {
        if model.isLoadingMore {
            AppLoadingState(title: "Loading more…").accessibilityIdentifier("search.loadingMore")
        } else if let error = model.pageError {
            AppErrorMessage(message: error.localizedDescription).accessibilityIdentifier("search.pageError")
            Button("Retry More Results") { model.loadMore() }.buttonStyle(AppActionStyle()).accessibilityIdentifier("search.retryMore")
        } else if model.nextPage != nil {
            Button("Load More") { model.loadMore() }.accessibilityIdentifier("search.loadMore")
        }
    }
}

import SwiftUI

struct SearchView: View {
    @Bindable var model: SearchModel

    var body: some View {
        List {
            Section {
                Picker("Media type", selection: $model.filter) {
                    ForEach(SearchFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("search.filters")
            }
            if model.usesTestData {
                Text("UI test data").font(.caption).accessibilityIdentifier("search.testData")
            }
            switch model.phase {
            case .idle:
                ContentUnavailableView("Find your next story", systemImage: "magnifyingglass",
                                       description: Text("Search for movies and TV shows."))
            case .loading:
                ProgressView("Searching…").accessibilityIdentifier("search.loading")
            case .cancelled:
                Text("Search canceled. Try again when you are ready.")
                Button("Retry Search") { model.retry() }.accessibilityIdentifier("search.retry")
            case .failed(let error):
                Section {
                    ContentUnavailableView("Search unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(error.localizedDescription))
                        .accessibilityIdentifier("search.error")
                    Button("Retry Search") { model.retry() }.accessibilityIdentifier("search.retry")
                }
            case .loaded:
                if model.items.isEmpty {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass",
                        description: Text(model.nextPage == nil
                            ? "Try another title or media filter."
                            : "No matching titles on this page. More pages are available below."))
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
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Movies and TV shows")
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(for: MediaDestination.self) { MediaDetailView(destination: $0) }
    }

    @ViewBuilder
    private var pagination: some View {
        if model.isLoadingMore {
            ProgressView("Loading more…").accessibilityIdentifier("search.loadingMore")
        } else if let error = model.pageError {
            Text(error.localizedDescription).accessibilityIdentifier("search.pageError")
            Button("Retry More Results") { model.loadMore() }.accessibilityIdentifier("search.retryMore")
        } else if model.nextPage != nil {
            Button("Load More") { model.loadMore() }.accessibilityIdentifier("search.loadMore")
        }
    }
}

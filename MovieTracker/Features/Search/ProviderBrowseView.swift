import SwiftUI

/// Used inside Search's List and inside a detail page's scroll content.
struct ProviderBrowseView: View {
    @Bindable var model: ProviderBrowseModel
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            if model.relatedTo == nil {
                if textSize.isAccessibilitySize { kindPicker.pickerStyle(.menu) }
                else { kindPicker.pickerStyle(.segmented) }
                Picker("Browse category", selection: $model.category) {
                    ForEach(ProviderBrowseModel.Category.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("browse.categories")
            }
            Text(model.heading).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(model.explanation).font(.subheadline).foregroundStyle(.secondary)
            if model.relatedTo == nil, model.category == .genres, !model.genres.isEmpty {
                Picker("Genre", selection: $model.selectedGenre) {
                    Text("Choose a genre").tag(String?.none)
                    ForEach(model.genres, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.menu).accessibilityIdentifier("browse.genres")
            }
            content
            if model.relatedTo == nil {
                if let url = URL(string: "https://www.themoviedb.org") { Link("Data provided by TMDB", destination: url) }
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(model.relatedTo == nil ? "browse.content" : "detail.similar")
        .task(id: model.key) { await model.load() }
        .onDisappear { model.cancelPagination() }
        .onChange(of: library.metadataReferenceDate) { _, now in model.expire(at: now) }
        .onChange(of: library.metadataInvalidation) { _, _ in model.invalidateSessionIfChanged() }
    }
    private func result(_ item: SearchItem) -> some View {
        NavigationLink(value: item.destination) {
            SearchResultRow(item: item, posterURL: model.imageResolver?.posterURL(reference: item.posterReference))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browse.result.\(item.id.kind.rawValue).\(item.id.value)")
    }
    private var kindPicker: some View {
        Picker("Browse media type", selection: $model.kind) {
            Text("Movies").tag(MediaID.Kind.movie)
            Text("TV Shows").tag(MediaID.Kind.tvShow)
        }.accessibilityIdentifier("browse.media")
    }
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            AppLoadingState(title: "Loading titles…").accessibilityIdentifier("browse.loading")
        case .chooseGenre:
            Text(model.genres.isEmpty ? "No genres are available for this media type." : "Select a genre to browse titles.")
                .accessibilityIdentifier("browse.chooseGenre")
        case .cancelled:
            Text("Browsing was canceled.")
            retry
        case .failed(let error):
            AppErrorMessage(message: error.localizedDescription).accessibilityIdentifier("browse.error")
            if !error.isConfigurationFailure && error != .unsupportedDiscovery { retry }
            if error.isConfigurationFailure { Text("Check your metadata configuration in Profile Settings.").font(.footnote) }
        case .loaded:
            if model.items.isEmpty {
                Text(model.relatedTo == nil ? "No titles are available in this selection." : "No similar titles are available.")
                    .accessibilityIdentifier("browse.empty")
            }
            if model.relatedTo == nil {
                LazyVStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    ForEach(model.items) { result($0) }
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                        ForEach(model.items) { result($0).frame(width: textSize.isAccessibilitySize ? 320 : 260, alignment: .leading) }
                    }
                }
            }
            if model.relatedTo == nil {
                Button("Refresh Titles") { model.retry() }.buttonStyle(AppActionStyle(emphasis: .tertiary))
            }
            if model.isLoadingMore { AppLoadingState(title: "Loading more…") }
            else if let error = model.pageError {
                AppErrorMessage(message: error.localizedDescription)
                Button("Retry More Titles") { model.loadMore() }.buttonStyle(AppActionStyle())
            } else if model.nextPage != nil {
                Button("Load More Titles") { model.loadMore() }.buttonStyle(AppActionStyle()).accessibilityIdentifier("browse.loadMore")
            }
        }
    }
    private var retry: some View {
        Button("Retry Browsing") { model.retry() }.buttonStyle(AppActionStyle()).accessibilityIdentifier("browse.retry")
    }
}

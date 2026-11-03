import Accessibility
import SwiftUI

struct MediaDetailView: View {
    @State private var model: MediaDetailModel
    @State private var refreshID = 0
    @Environment(LibraryStore.self) private var library

    init(model: MediaDetailModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                if model.usesTestData { Text("UI test data").font(.caption) }
                if let snapshot = model.snapshot(at: max(library.metadataReferenceDate, Date.now)) {
                    if let error = model.error {
                        AppErrorMessage(message: (model.hasSavedMetadata ? "Showing saved details. " : "Provider metadata unavailable. ") + error.localizedDescription)
                            .accessibilityIdentifier("details.cached")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Text(model.availability.message).font(.footnote).accessibilityIdentifier("details.availability")
                    if let date = model.availability.retrievedAt {
                        Text("Last retrieved: " + date.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                    }
                    DetailArtworkHeader(item: SearchItem(snapshot.media), backdropReference: backdrop(snapshot.media), resolver: snapshot.imageResolver, savedPosterURL: model.cachedPosterURL)
                        .id(refreshID)
                    LibraryDetailActions(media: snapshot.media,
                        posterURL: snapshot.imageResolver?.posterURL(reference: SearchItem(snapshot.media).posterReference))
                    PersonalDiarySection(media: snapshot.media)
                    switch snapshot.media {
                    case .movie(let movie): MovieDetailContent(movie: movie)
                    case .tvShow(let show):
                        TVDetailContent(show: show)
                        TVSeasonsSection(show: show, catalogIsFresh: model.hasCurrentMetadata, model: model.tvProgressModel(for: show))
                    }
                    DetailCast(members: snapshot.cast, isLoading: model.isLoadingExtras, unavailable: model.castUnavailable)
                    if model.artworkUnavailable {
                        Text("Artwork could not be updated. Previously loaded artwork may still be available.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.isLoading { AppLoadingState(title: "Updating details…") }
                    if !model.usesTestData {
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let url = URL(string: "https://www.themoviedb.org") { Link("Data provided by TMDB", destination: url) }
                    }
                } else {
                    Text(model.destination.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.destination.id.kind == .movie ? "Movie" : "TV Show").font(.headline)
                    if model.isLoading {
                        AppLoadingState(title: "Loading details…").accessibilityIdentifier("details.loading")
                    } else if let error = model.error {
                        EmptyStateCard(title: "Details unavailable", systemImage: "exclamationmark.triangle",
                                       message: error.localizedDescription, presentation: .inline)
                            .accessibilityIdentifier("details.error")
                    } else if model.wasCancelled {
                        Text("Loading was canceled. Try again when you are ready.")
                    }
                }
                if model.canRefresh && !model.isLoading && !model.isLoadingExtras {
                    Button(model.error == nil && !model.castUnavailable && !model.artworkUnavailable ? "Refresh Details" : "Retry Details") {
                        refreshID += 1
                    }
                    .buttonStyle(AppActionStyle())
                    .accessibilityIdentifier("details.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.Layout.contentMargin)
        }
        .background(AppStyle.background)
        .appPageTitle("Details")
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("media.details")
        .onChange(of: library.metadataReferenceDate) { _, now in model.expireMetadata(at: now) }
        .onChange(of: library.metadataInvalidation) { _, _ in model.invalidateProviderMetadata() }
        .task(id: refreshID) { await model.load(store: library, force: refreshID > 0) }
        .onChange(of: model.isLoading) { _, loading in
            if loading { AccessibilityNotification.Announcement("Loading details").post() }
        }
        .onChange(of: model.error) { _, error in
            if let error { AccessibilityNotification.Announcement(error.localizedDescription).post() }
        }
    }
    private func backdrop(_ media: MediaSearchResult) -> String? {
        switch media {
        case .movie(let movie): movie.backdropReference
        case .tvShow(let show): show.backdropReference
        }
    }

}

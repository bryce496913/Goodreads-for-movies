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
                    DetailArtworkHeader(item: SearchItem(snapshot.media), backdropReference: backdrop(snapshot.media), resolver: snapshot.imageResolver, savedPosterURL: model.posterURL(at: max(library.metadataReferenceDate, Date.now)))
                        .id(refreshID)
                    metadataRecovery(snapshot.media)
                    switch snapshot.media {
                    case .movie(let movie): MovieDetailContent(movie: movie)
                    case .tvShow(let show):
                        TVDetailContent(show: show)
                    }
                    LibraryDetailActions(media: snapshot.media,
                        posterURL: snapshot.imageResolver?.posterURL(reference: SearchItem(snapshot.media).posterReference))
                    switch snapshot.media {
                    case .movie(let movie): DetailSynopsis(overview: movie.overview)
                    case .tvShow(let show):
                        TVSeasonsSection(show: show, catalogIsFresh: model.hasCurrentMetadata, model: model.tvProgressModel(for: show))
                        DetailSynopsis(overview: show.overview)
                    }
                    DetailCast(members: snapshot.cast, isLoading: model.isLoadingExtras, unavailable: model.castUnavailable)
                    PersonalDiarySection(media: snapshot.media)
                    ProviderBrowseView(model: model.relatedTitles)
                    if !model.usesTestData {
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let url = URL(string: "https://www.themoviedb.org") { Link("Data provided by TMDB", destination: url) }
                    }
                } else {
                    Text(MetadataPolicy.presentationTitle(model.destination.title, for: model.destination.id)).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
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
                if model.snapshot == nil { refreshAction }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.Layout.contentMargin)
        }
        .safeAreaPadding(.bottom, AppStyle.Layout.contentMargin)
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
    @ViewBuilder private func metadataRecovery(_ media: MediaSearchResult) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            if let message = model.persistenceErrorMessage {
                AppErrorMessage(message: message).accessibilityIdentifier("details.saveError")
            } else if let error = model.error {
                AppErrorMessage(message: (model.hasSavedMetadata ? "Showing saved information. " : "Title information unavailable. ") + error.localizedDescription)
                    .accessibilityIdentifier("details.cached")
            } else {
                Text(model.availability.message).font(.footnote).accessibilityIdentifier("details.availability")
            }
            if model.hasSavedMetadata {
                let missing = DetailMetadataRecovery.missingFields(in: media)
                if !missing.isEmpty {
                    Text("Not provided: " + missing.joined(separator: ", ") + ". Refresh can check for updates.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("details.incomplete")
                }
            }
            if model.isLoading { AppLoadingState(title: "Updating title information…") }
            else if model.wasCancelled { Text("Update canceled. Saved personal records are kept.").font(.footnote) }
            if model.artworkUnavailable { Text("Artwork unavailable. Refresh can try again.").font(.footnote) }
            refreshAction
            if let date = model.availability.retrievedAt {
                Text("Last retrieved: " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var refreshAction: some View {
        if model.canRefresh && !model.isLoading && !model.isLoadingExtras {
            Button(model.error == nil && model.persistenceErrorMessage == nil && !model.castUnavailable && !model.artworkUnavailable ? "Refresh Details" : "Retry Details") {
                refreshID += 1
            }
            .buttonStyle(AppActionStyle(emphasis: .tertiary))
            .accessibilityIdentifier("details.retry")
            .accessibilityHint("Updates provider information while keeping ratings, reviews, history and collections.")
        } else if !model.canRefresh && !model.hasSavedMetadata && !model.isLoading {
            Text("Add provider configuration in Profile Settings to retrieve title information. Your saved personal records are still available.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func backdrop(_ media: MediaSearchResult) -> String? {
        switch media {
        case .movie(let movie): movie.backdropReference
        case .tvShow(let show): show.backdropReference
        }
    }

}

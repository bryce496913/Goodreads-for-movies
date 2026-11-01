import Accessibility
import SwiftUI

struct MediaDetailView: View {
    @State private var model: MediaDetailModel
    @State private var refreshID = 0

    init(model: MediaDetailModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                if model.usesTestData { Text("UI test data").font(.caption) }
                if let snapshot = model.snapshot {
                    if let error = model.error {
                        Text("Showing previously loaded details. \(error.localizedDescription)")
                            .accessibilityIdentifier("details.cached")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    DetailArtworkHeader(item: SearchItem(snapshot.media), backdropReference: backdrop(snapshot.media), resolver: snapshot.imageResolver)
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
                    if model.isLoading { ProgressView("Updating details…") }
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
                        ProgressView("Loading details…").accessibilityIdentifier("details.loading")
                    } else if let error = model.error {
                        ContentUnavailableView("Details unavailable", systemImage: "exclamationmark.triangle",
                                               description: Text(error.localizedDescription))
                            .accessibilityIdentifier("details.error")
                    } else if model.wasCancelled {
                        Text("Loading was canceled. Try again when you are ready.")
                    }
                }
                if !model.isLoading && !model.isLoadingExtras {
                    Button(model.error == nil && !model.castUnavailable && !model.artworkUnavailable ? "Refresh Details" : "Retry Details") {
                        refreshID += 1
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("details.retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("media.details")
        .task(id: refreshID) { await model.load() }
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

import SwiftUI

struct DashboardTitleRow: View {
    let title: DashboardTitle
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LibraryCachedPoster(url: title.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(title.id.kind == .movie ? "Movie" : "TV Show").font(.subheadline)
                if let year = title.year { Text(String(year)).font(.subheadline) }
                if let rating = title.rating { Text("Your rating: " + rating.label).font(.subheadline) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DashboardDiaryRow: View {
    let item: DashboardDiaryItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashboardTitleRow(title: item.title)
            if let date = item.watchedDate { Text("Watched: " + DetailFormatting.date(date)) }
            else { Text("Watch date unknown • Recorded: " + DetailFormatting.date(item.recordedAt)) }
        }
    }
}

struct DashboardReadState: View {
    @Environment(LibraryStore.self) private var library
    let model: DashboardModel
    var body: some View {
        if let error = library.loadError {
            Section {
                Text("Saved data could not be refreshed. Any displayed information is the last loaded snapshot.")
                Text(error.localizedDescription)
                Button("Retry Saved Data") { library.reload() }
            }
        }
        if model.isLoading { ProgressView("Updating your viewing summary…") }
        if let snapshot = model.snapshot,
           snapshot.duplicateTitles + snapshot.invalidRatings + snapshot.unclassifiedTitles > 0 {
            Text("Some saved records need attention: \(snapshot.duplicateTitles) duplicate identities, \(snapshot.invalidRatings) invalid ratings, \(snapshot.unclassifiedTitles) unrecognized titles. Counts exclude invalid values; no records were changed.")
                .font(.footnote)
        }
    }
}

struct SavedMediaNavigation: ViewModifier {
    @Environment(LibraryStore.self) private var library
    let detailModel: (MediaDestination, MediaSearchResult?) -> MediaDetailModel
    func body(content: Content) -> some View {
        content.navigationDestination(for: MediaDestination.self) { destination in
            let media = library.entry(for: destination.id)?.offlineMedia
                ?? library.events(for: destination.id).first?.savedMedia
                ?? library.reviews(for: destination.id).first?.savedMedia
                ?? library.savedTVShow(for: destination.id).map { .tvShow($0) }
            MediaDetailView(model: detailModel(destination, media))
        }
    }
}

import SwiftUI

struct DashboardTitleRow: View {
    let title: DashboardTitle
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    LibraryCachedPoster(url: title.posterURL)
                    details
                }
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.compact) {
                    LibraryCachedPoster(url: title.posterURL)
                    details
                }
            }
        }
        .padding(.vertical, AppStyle.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Text(title.title).font(AppStyle.Typography.mediaTitle)
                .foregroundStyle(AppStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text([title.id.kind == .movie ? "Movie" : "TV Show", title.year.map(String.init)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            if let rating = title.rating {
                PersonalRatingDisplay(rating: rating, label: "Your rating: " + rating.label)
            }
        }
    }

}

struct DashboardDiaryRow: View {
    let item: DashboardDiaryItem
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            DashboardTitleRow(title: item.title)
            Group {
                if let date = item.watchedDate { Label("Watched: " + DetailFormatting.date(date), systemImage: "calendar") }
                else { Label("Watch date unknown • Recorded: " + DetailFormatting.date(item.recordedAt), systemImage: "calendar.badge.clock") }
            }
            .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DashboardReadState: View {
    @Environment(LibraryStore.self) private var library
    let model: DashboardModel
    var body: some View {
        if let warning = library.metadataWarning { Text(warning).font(.footnote) }
        if let error = library.loadError {
            Section {
                Text("Saved data could not be refreshed. Any displayed information is the last loaded snapshot.")
                Text(error.localizedDescription)
                Button("Retry Saved Data") { library.reload() }
            }
        }
        if model.isLoading { AppLoadingState(title: "Updating your viewing summary…") }
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
            let media = library.offlineMedia(for: destination.id)
            MediaDetailView(model: detailModel(destination, media))
        }
    }
}

/// Native rows, not metric cards. Long text and accessibility sizes use a vertical layout.
struct DashboardMetricRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            if textSize.isAccessibilitySize { stacked }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.medium) {
                        Text(label).font(AppStyle.Typography.metadata).fixedSize()
                        Spacer(minLength: AppStyle.Spacing.small)
                        Text(value).font(AppStyle.Typography.mediaTitle).monospacedDigit().fixedSize()
                    }
                    stacked
                }
            }
        }
        .foregroundStyle(AppStyle.Colors.primaryText)
        .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ", " + value)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Text(label).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            Text(value).font(AppStyle.Typography.mediaTitle).monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

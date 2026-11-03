import SwiftUI

struct DetailArtwork: View {
    let title: String
    let kind: String
    let url: URL?
    let aspectRatio: CGFloat

    var body: some View {
        Rectangle().fill(AppStyle.Colors.raisedSurface)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                EphemeralAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .accessibilityLabel("\(kind) for \(title)")
                    case .empty where url != nil:
                        ProgressView().accessibilityLabel("Loading \(kind.lowercased()) for \(title)")
                    default:
                        ArtworkPlaceholder(systemImage: "photo")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(kind) unavailable for \(title)")
                            .accessibilityIdentifier("details.\(kind.lowercased()).placeholder")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: aspectRatio < 1 ? AppStyle.Radius.poster : AppStyle.Radius.artwork))
    }
}

struct DetailArtworkHeader: View {
    let item: SearchItem
    let backdropReference: String?
    let resolver: MetadataImageResolver?
    var savedPosterURL: URL? = nil
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            if let url = resolver?.backdropURL(reference: backdropReference, size: .detail) {
                DetailArtwork(title: item.title, kind: "Backdrop", url: url, aspectRatio: 16 / 9)
            }
            if dynamicType.isAccessibilitySize {
                poster.frame(maxWidth: 160)
                title
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                    poster.frame(width: 112)
                    title
                }
            }
        }
    }

    private var poster: some View {
        DetailArtwork(title: item.title, kind: "Poster",
                      url: resolver?.posterURL(reference: item.posterReference, size: .card) ?? savedPosterURL, aspectRatio: 2 / 3)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(AppStyle.Typography.pageTitle).foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("details.title")
            MediaTypeLabel(title: item.mediaType)
            if let year = item.year { Text(String(year)).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

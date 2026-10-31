import SwiftUI

struct DetailArtwork: View {
    let title: String
    let kind: String
    let url: URL?
    let aspectRatio: CGFloat

    var body: some View {
        Rectangle().fill(AppStyle.surface)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .accessibilityLabel("\(kind) for \(title)")
                    case .empty where url != nil:
                        ProgressView().accessibilityLabel("Loading \(kind.lowercased()) for \(title)")
                    default:
                        Image(systemName: "photo")
                            .font(.title2).foregroundStyle(.secondary)
                            .accessibilityLabel("\(kind) unavailable for \(title)")
                            .accessibilityIdentifier("details.\(kind.lowercased()).placeholder")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DetailArtworkHeader: View {
    let item: SearchItem
    let backdropReference: String?
    let resolver: MetadataImageResolver?
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            DetailArtwork(title: item.title, kind: "Backdrop",
                          url: resolver?.backdropURL(reference: backdropReference, size: .detail), aspectRatio: 16 / 9)
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
                      url: resolver?.posterURL(reference: item.posterReference, size: .card), aspectRatio: 2 / 3)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("details.title")
            Text(item.mediaType).font(.headline)
            if let year = item.year { Text(String(year)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

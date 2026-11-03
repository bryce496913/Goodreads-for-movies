import SwiftUI

struct SearchResultRow: View {
    let item: SearchItem
    let posterURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            PosterFrame {
                EphemeralAsyncImage(url: posterURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ArtworkPlaceholder()
                    }
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                Text(item.title).font(AppStyle.Typography.mediaTitle).foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
                MediaTypeLabel(title: item.mediaType)
                if let year = item.year {
                    Text(String(year)).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.vertical, AppStyle.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: ", "))
    }
}

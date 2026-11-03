import SwiftUI

struct SearchResultRow: View {
    let item: SearchItem
    let posterURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            PosterFrame(width: 72) {
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
                Text([item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppStyle.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: ", "))
    }
}

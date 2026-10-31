import SwiftUI

struct SearchResultRow: View {
    let item: SearchItem
    let posterURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            AsyncImage(url: posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(AppStyle.surface)
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 56, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(item.mediaType).font(.subheadline).foregroundStyle(.secondary)
                if let year = item.year {
                    Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, AppStyle.Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: ", "))
    }
}

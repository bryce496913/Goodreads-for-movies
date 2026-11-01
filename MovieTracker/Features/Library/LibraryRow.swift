import SwiftUI
import UIKit

struct LibraryRow: View {
    let item: LibraryItem
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) { LibraryCachedPoster(url: item.posterURL); details }
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { LibraryCachedPoster(url: item.posterURL); details }
            }
        }
        .padding(.vertical, AppStyle.Spacing.small)
        .accessibilityElement(children: .combine)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(item.mediaLabel).font(.subheadline).foregroundStyle(.secondary)
            if let year = item.year { Text(String(year)).font(.subheadline).foregroundStyle(.secondary) }
            Text(item.statusLabel).font(.subheadline)
            Text(item.rating.label).font(.subheadline)
            if item.isFavorite { Label("Favorite", systemImage: "heart.fill").font(.subheadline) }
        }
    }
}

/// Read the existing OS response cache only. Local Library filtering never starts image requests.
private struct LibraryCachedPoster: View {
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Rectangle().fill(AppStyle.surface); Image(systemName: "film").foregroundStyle(.secondary) } }
        }
        .frame(width: 56, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard !Task.isCancelled, let url, let response = URLCache.shared.cachedResponse(for: URLRequest(url: url)) else { return }
            image = UIImage(data: response.data)
        }
    }
}

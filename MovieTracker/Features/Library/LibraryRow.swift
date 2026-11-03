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
            Text(item.title).font(AppStyle.Typography.mediaTitle).foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
            MediaTypeLabel(title: item.mediaLabel)
            if let year = item.year { Text(String(year)).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText) }
            Text(item.statusLabel).font(AppStyle.Typography.metadata)
            Text(item.rating.label).font(AppStyle.Typography.metadata)
            if item.isFavorite { Label("Favorite", systemImage: "heart.fill").font(AppStyle.Typography.metadata) }
        }
    }
}

/// Read the bounded in-memory artwork cache only. Local Library filtering never starts image requests.
struct LibraryCachedPoster: View {
    let url: URL?
    @State private var image: UIImage?
    @Environment(LibraryStore.self) private var library
    var body: some View {
        PosterFrame {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ArtworkPlaceholder() }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard !Task.isCancelled, let url else { return }
            image = ProviderArtworkCache.shared.image(url)
        }
        .onChange(of: library.metadataReferenceDate) { _, now in
            image = url.flatMap { ProviderArtworkCache.shared.image($0, at: now) }
        }
    }
}

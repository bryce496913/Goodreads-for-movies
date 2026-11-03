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
    private var statusSymbol: String {
        switch item.rawStatus {
        case "watchlist": "bookmark"
        case "watching": "play.circle"
        case "watched": "checkmark.circle"
        default: "minus.circle"
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(AppStyle.Typography.mediaTitle).foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
            Text([item.mediaLabel, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            Label(item.statusLabel, systemImage: statusSymbol)
                .font(AppStyle.Typography.metadata)
            PersonalRatingDisplay(rating: item.rating.value, label: item.rating.label)
            if item.isFavorite {
                Label("Favorite", systemImage: "heart.fill")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            }
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

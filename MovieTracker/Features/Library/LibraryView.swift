import SwiftUI

struct LibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                Text("Your movies and TV, together.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                EmptyStateCard(
                    title: "Watchlist", systemImage: "bookmark",
                    message: "A place for movies and shows you want to watch. Saving titles is coming in a future update."
                )
                .accessibilityIdentifier("library.watchlist")
                EmptyStateCard(
                    title: "Watching", systemImage: "play.circle",
                    message: "Movies and shows you are watching will appear here."
                )
                EmptyStateCard(
                    title: "Watched", systemImage: "checkmark.circle",
                    message: "Your viewing history will grow here."
                )
                EmptyStateCard(
                    title: "Favorites", systemImage: "heart",
                    message: "Keep your favorite stories close. Favorites will be available in a future update."
                )
            }
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Library")
    }
}

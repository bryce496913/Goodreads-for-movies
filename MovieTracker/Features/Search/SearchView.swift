import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            EmptyStateCard(
                title: query.isEmpty ? "Find your next story" : "Search is coming soon",
                systemImage: "magnifyingglass",
                message: "Movies and TV shows will be searchable here in a future update. No searches are sent yet."
            )
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies and TV shows")
        .autocorrectionDisabled()
    }
}

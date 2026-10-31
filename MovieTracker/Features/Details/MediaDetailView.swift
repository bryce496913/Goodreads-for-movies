import SwiftUI

/// Replace this body with full metadata details in the next pass; retain the typed route.
struct MediaDetailView: View {
    let destination: MediaDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                Text(destination.title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(destination.id.kind == .movie ? "Movie" : "TV Show")
                    .font(.headline)
                if let year = destination.year {
                    Text(String(year)).foregroundStyle(.secondary)
                }
                Text("More details will be available in a future update.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("media.details")
    }
}

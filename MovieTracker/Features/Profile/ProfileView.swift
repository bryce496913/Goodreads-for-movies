import SwiftUI

struct ProfileView: View {
    let dashboard: DashboardModel
    var body: some View {
        List {
            Section {
                Label("Your local profile", systemImage: "person.crop.circle").font(.title2)
                Text("Your private viewing story on this device. No account is needed.")
            }
            DashboardReadState(model: dashboard)
            if let snapshot = dashboard.snapshot {
                let stats = snapshot.statistics
                Section("Viewing Statistics") {
                    metric("Unique movies watched", stats.watchedMovies, id: "movies")
                    metric("Series with watched episode progress", stats.seriesWithProgress, id: "series")
                    metric("Unique episodes marked watched", stats.watchedEpisodes, id: "episodes")
                    metric("Watchlist titles", stats.watchlist, id: "watchlist")
                    metric("Favorite titles", stats.favorites, id: "favorites")
                    metric("Personally rated titles", stats.ratings, id: "ratings")
                    VStack(alignment: .leading) {
                        Text("Average personal rating").font(.headline)
                        Text(stats.averageRating.map { $0.formatted(.number.precision(.fractionLength(1))) + " out of 5 stars" } ?? "Unavailable — no valid personal ratings")
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("profile.average")
                    metric("Written reviews", stats.reviews, id: "reviews")
                    metric("Recorded viewing events", stats.viewingEvents, id: "events")
                }
                Section("What These Counts Mean") {
                    Text("Movies count distinct titles marked Watched or logged as watched, including undated watches. Future dated watches are excluded. Rewatches add viewing events, not duplicate movies.")
                    Text("Series and episode counts use current watched episode flags, including specials. A series marked Watched alone does not invent episode progress. Unmarking an episode updates these counts.")
                    Text("Ratings use valid personal half-star values only. Unrated titles do not lower the average. Reviews count saved review records, including retained legacy reviews.")
                }.font(.footnote)
                Section("Recent Viewing Diary") {
                    if snapshot.recentDiary.isEmpty { Text("No viewing events yet. Record a watch from a title’s detail page.").accessibilityIdentifier("profile.emptyDiary") }
                    ForEach(snapshot.recentDiary) { item in
                        NavigationLink(value: item.title.destination) { DashboardDiaryRow(item: item) }
                    }
                    NavigationLink("All Viewing History") { ViewingHistoryView() }
                }
            }
            Section {
                NavigationLink {
                    ContentUnavailableView("Settings coming soon", systemImage: "gearshape", description: Text("Preferences will be available in a future update."))
                        .navigationTitle("Settings")
                } label: { Label("Settings", systemImage: "gearshape") }
                .accessibilityIdentifier("profile.settings")
            }
        }
        .navigationTitle("Profile")
    }
    private func metric(_ label: String, _ value: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            Text(value.formatted()).font(.title3.monospacedDigit())
        }.accessibilityElement(children: .combine).accessibilityIdentifier("profile.stat." + id)
    }
}

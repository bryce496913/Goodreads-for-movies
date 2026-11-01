import SwiftUI

struct HomeView: View {
    let dashboard: DashboardModel
    let progressModel: (TVShow) -> TVProgressModel
    let openSearch: () -> Void
    let openLibrary: () -> Void

    var body: some View {
        List {
            DashboardReadState(model: dashboard)
            if let snapshot = dashboard.snapshot {
                if !snapshot.hasPersonalData {
                    Section {
                        ContentUnavailableView("Your viewing story starts here", systemImage: "play.rectangle",
                            description: Text("Find a movie or series, save a title, or record a watch. Your personal activity will appear here."))
                        Button("Find Movies and TV", action: openSearch).accessibilityIdentifier("home.findTitles")
                    }.accessibilityIdentifier("home.empty")
                }
                Section("Continue Watching") {
                    if snapshot.continueWatching.isEmpty { Text("No unfinished series with saved episode progress.") }
                    ForEach(snapshot.continueWatching) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink(value: item.title.destination) { DashboardTitleRow(title: item.title) }
                            Text("\(item.progress.watched) of \(item.progress.eligible) known aired regular episodes watched")
                            if let percent = item.progress.percentage { ProgressView(value: Double(percent), total: 100).accessibilityLabel("Aired episode progress") }
                            else { Text("A reliable aired-episode percentage is unavailable.").font(.footnote) }
                            if let next = item.next {
                                NavigationLink {
                                    TVSeasonEpisodesView(number: next.seasonNumber, model: progressModel(item.show))
                                } label: { Text("Next: Season \(next.seasonNumber), Episode \(next.number) — \(next.title)") }
                                .accessibilityIdentifier("home.nextEpisode")
                            } else {
                                Text("Next episode unavailable from saved metadata.")
                                if let last = item.lastMarked {
                                    Text("Last marked watched: Season \(last.seasonNumber), Episode \(last.number)").font(.footnote)
                                }
                            }
                        }
                    }
                }
                Section("Recently Watched") {
                    if snapshot.recentlyWatched.isEmpty { Text("No dated watches recorded yet. Undated watches remain in Viewing History.") }
                    ForEach(snapshot.recentlyWatched) { item in
                        NavigationLink(value: item.title.destination) { DashboardDiaryRow(item: item) }
                    }
                    NavigationLink("Viewing History") { ViewingHistoryView() }.accessibilityIdentifier("home.history")
                }
                Section("From Your Watchlist") {
                    if snapshot.watchlist.isEmpty { Text("Your Watchlist is empty. Save titles from Search to plan your next watch.") }
                    ForEach(snapshot.watchlist) { item in
                        NavigationLink(value: item.destination) { DashboardTitleRow(title: item) }
                    }
                    Button("Open Library", action: openLibrary).accessibilityIdentifier("home.openLibrary")
                }
                Section("Recent Personal Activity") {
                    if snapshot.activity.isEmpty { Text("No recorded activity yet. Older ratings without a known rating timestamp are not dated here.") }
                    ForEach(snapshot.activity) { item in
                        NavigationLink(value: item.title.destination) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title.title).font(.headline)
                                Text(item.label)
                                Text("Recorded: " + item.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                if let watched = item.watchedDate { Text("Watch date: " + DetailFormatting.date(watched)).font(.subheadline) }
                            }
                        }
                    }
                }
            } else if !dashboard.isLoading { Text("Your saved summary is not available yet.") }
        }
        .navigationTitle("Welcome")
        .listStyle(.insetGrouped)
    }
}

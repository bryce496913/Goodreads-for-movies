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
                        EmptyStateCard(title: "Your viewing story starts here", systemImage: "play.rectangle",
                            message: "Find a movie or series, save a title, or record a watch. Your personal activity will appear here.", presentation: .inline)
                        Button("Find Movies and TV", action: openSearch).buttonStyle(AppActionStyle(emphasis: .primary)).accessibilityIdentifier("home.findTitles")
                    }.accessibilityIdentifier("home.empty")
                }
                if snapshot.hasPersonalData {
                    Section("Continue Watching") {
                        if snapshot.continueWatching.isEmpty { Text("No unfinished series with saved episode progress.") }
                        ForEach(snapshot.continueWatching) { item in
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                                NavigationLink(value: item.title.destination) { DashboardTitleRow(title: item.title) }
                                ProgressDescription(summary: item.progress, series: true, compact: true)
                                if let next = item.next {
                                    NavigationLink {
                                        TVSeasonEpisodesView(number: next.seasonNumber, model: progressModel(item.show))
                                    } label: {
                                        Label("Next: Season \(next.seasonNumber), Episode \(next.number) — \(next.title)", systemImage: "play.circle")
                                            .font(AppStyle.Typography.mediaTitle)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
                                    }
                                    .accessibilityIdentifier("home.nextEpisode")
                                } else {
                                    Text("Next episode unavailable from saved metadata.")
                                    if let last = item.lastMarked {
                                        Text(last.number == 0 ? "Watched episode reference: " + last.id.providerValue : "Last marked watched: Season \(last.seasonNumber), Episode \(last.number)").font(.footnote)
                                    }
                                }
                            }
                        }
                    }
                    Section("Recent Personal Activity") {
                        if snapshot.activity.isEmpty { Text("No recorded activity yet. Older ratings without a known rating timestamp are not dated here.") }
                        ForEach(snapshot.activity) { item in
                            NavigationLink(value: item.title.destination) {
                                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                                    Text(item.title.title).font(AppStyle.Typography.mediaTitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.label).font(AppStyle.Typography.metadata)
                                    Text("Recorded: " + item.date.formatted(date: .abbreviated, time: .shortened)).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                                    if let watched = item.watchedDate { Text("Watch date: " + DetailFormatting.date(watched)).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText) }
                                }
                            }
                        }
                    }
                    Section("Recently Watched") {
                        if snapshot.recentlyWatched.isEmpty { Text("No dated watches recorded yet. Undated watches remain in Viewing History.") }
                        ForEach(snapshot.recentlyWatched) { item in
                            NavigationLink(value: item.title.destination) { DashboardDiaryRow(item: item) }
                                .accessibilityIdentifier("home.recentWatch")
                        }
                        NavigationLink("Viewing History") { ViewingHistoryView() }.accessibilityIdentifier("home.history")
                    }
                    Section("From Your Watchlist") {
                        if snapshot.watchlist.isEmpty { Text("Your Watchlist is empty. Save titles from Search to plan your next watch.") }
                        ForEach(snapshot.watchlist) { item in
                            NavigationLink(value: item.destination) { DashboardTitleRow(title: item) }
                        }
                        Button("Open Library", action: openLibrary).buttonStyle(AppActionStyle()).accessibilityIdentifier("home.openLibrary")
                    }
                }
            } else if !dashboard.isLoading { Text("Your saved summary is not available yet.") }
        }
        .appListScreen(AppTab.home.title, isRoot: true)
        .accessibilityIdentifier("screen.home")
    }
}

import SwiftUI

struct HomeView: View {
    let dashboard: DashboardModel
    let progressModel: (TVShow) -> TVProgressModel
    let openSearch: () -> Void
    let openLibrary: () -> Void

    var body: some View {
        List {
            Section {
                Text("Pick up where you left off.")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            }
            DashboardReadState(model: dashboard)
            if let snapshot = dashboard.snapshot {
                if !snapshot.hasPersonalData {
                    Section {
                        EmptyStateCard(title: "Your viewing story starts here", systemImage: "play.rectangle",
                            message: "Find a movie or series, save a title, or record a watch. Your personal activity will appear here.", presentation: .inline)
                        Button("Find Movies and TV", action: openSearch).buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true)).accessibilityIdentifier("home.findTitles")
                    }.accessibilityIdentifier("home.empty")
                }
                if snapshot.hasPersonalData {
                    Section("Continue Watching") {
                        if snapshot.continueWatching.isEmpty { Text("No unfinished series with saved episode progress.") }
                        ForEach(snapshot.continueWatching) { item in
                            HomeContinueWatchingRow(item: item, progressModel: progressModel)
                        }
                    }
                    Section("Recent Personal Activity") {
                        let activity = HomePresentation.activity(in: snapshot)
                        if activity.isEmpty { Text("Your personal updates will appear here.") }
                        ForEach(activity) { item in
                            NavigationLink(value: item.title.destination) { HomeActivityRow(item: item) }
                                .accessibilityIdentifier("home.activity." + item.id)
                        }
                    }
                    Section("Recently Watched") {
                        if snapshot.recentlyWatched.isEmpty { Text("Your recent watches will appear here.") }
                        ForEach(snapshot.recentlyWatched) { item in
                            NavigationLink(value: item.title.destination) { DashboardDiaryRow(item: item) }
                                .accessibilityIdentifier("home.recentWatch")
                        }
                        NavigationLink("Viewing History") { ViewingHistoryView() }.accessibilityIdentifier("home.history")
                    }
                    Section("From Your Watchlist") {
                        if snapshot.watchlist.isEmpty {
                            EmptyStateCard(title: "Start your watchlist", systemImage: "bookmark",
                                message: "Save movies and shows you want to watch.", presentation: .inline)
                            Button("Find Movies and TV", action: openSearch)
                                .buttonStyle(AppActionStyle()).accessibilityIdentifier("home.watchlistSearch")
                        }
                        ForEach(snapshot.watchlist) { item in
                            NavigationLink(value: item.destination) { DashboardTitleRow(title: item) }
                        }
                        Button("Open Library", action: openLibrary).buttonStyle(AppActionStyle()).accessibilityIdentifier("home.openLibrary")
                    }
                }
            } else if !dashboard.isLoading { Text("Your saved summary is not available yet.") }
        }
        .appListScreen("Your screen", isRoot: true)
        .accessibilityIdentifier("screen.home")
    }
}

/// Small, presentation-only projections of already bounded dashboard previews (at most 8 and 5 rows).
enum HomePresentation {
    static func activity(in snapshot: DashboardSnapshot) -> [DashboardActivity] {
        let shownViewings = Set(snapshot.recentlyWatched.map { "viewing:" + $0.id.uuidString })
        return snapshot.activity.filter { !shownViewings.contains($0.id) }
    }
    static func watchedCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "episode" : "episodes") watched"
    }
    static func activityLabel(_ item: DashboardActivity) -> String {
        let prefix = "Personal rating updated: "
        if item.label.hasPrefix(prefix) { return "Rated " + item.label.dropFirst(prefix.count) }
        if item.label == "Personal rating cleared" { return "Rating cleared" }
        return item.label
    }
}

struct HomeActivityRow: View {
    let item: DashboardActivity
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            Text(item.title.title).font(AppStyle.Typography.mediaTitle)
                .foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
            Text(HomePresentation.activityLabel(item) + " · " + item.date.formatted(date: .abbreviated, time: .shortened))
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let watched = item.watchedDate {
                Text("Watch date: " + DetailFormatting.date(watched)).font(AppStyle.Typography.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title.title + ", " + item.label + ", Recorded: "
            + item.date.formatted(date: .abbreviated, time: .shortened)
            + (item.watchedDate.map { ", Watch date: " + DetailFormatting.date($0) } ?? ""))
    }
}

struct HomeContinueWatchingRow: View {
    let item: ContinueWatchingItem
    let progressModel: (TVShow) -> TVProgressModel
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) { poster; content }
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { poster; content }
            }
        }
        .padding(.vertical, AppStyle.Spacing.xSmall)
    }
    private var poster: some View { LibraryCachedPoster(url: item.title.posterURL) }
    private var content: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            NavigationLink(value: item.title.destination) {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                    Text(item.title.title).font(AppStyle.Typography.mediaTitle)
                        .foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
                    if let percentage = item.progress.percentage {
                        Text("\(item.progress.watched) of \(item.progress.eligible) known aired regular episodes watched")
                            .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                        ProgressView(value: Double(percentage), total: 100)
                            .accessibilityLabel("Known aired regular episode progress")
                            .accessibilityValue("\(percentage) percent")
                            .accessibilityIdentifier("home.progress")
                    } else {
                        Text(HomePresentation.watchedCount(item.progress.totalWatched))
                            .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                    }
                    if let last = item.lastMarked, last.number > 0 {
                        Text("Last watched: S\(last.seasonNumber) E\(last.number)")
                            .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                    }
                }
            }
            .accessibilityIdentifier("home.series." + item.id.value)
            if let next = item.next {
                NavigationLink {
                    TVSeasonEpisodesView(number: next.seasonNumber, model: progressModel(item.show))
                } label: {
                    Label("Continue · S\(next.seasonNumber) E\(next.number)", systemImage: "play.circle.fill")
                        .font(AppStyle.Typography.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
                }
                .accessibilityLabel("Continue " + item.title.title + ", season \(next.seasonNumber), episode \(next.number), " + next.title)
                .accessibilityIdentifier("home.nextEpisode")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

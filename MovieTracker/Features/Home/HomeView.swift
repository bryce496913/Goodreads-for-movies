import SwiftUI
import UIKit
import Observation

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
                    Section {
                        if snapshot.continueWatching.isEmpty { Text("No unfinished series with saved episode progress.") }
                        ForEach(snapshot.continueWatching) { item in
                            HomeContinueWatchingRow(item: item, progressModel: progressModel)
                        }
                    } header: { Text("Continue Watching") } footer: {
                        Text("Progress covers known aired regular episodes, not permanent series completion. Open a series for its saved seasons.")
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
            Text(activityDescription)
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let watched = item.watchedDate {
                Text("Watch date: " + DetailFormatting.date(watched)).font(AppStyle.Typography.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenDescription))
    }
    private var recordedDate: String {
        item.date.formatted(date: .abbreviated, time: .shortened)
    }
    private var activityDescription: String {
        [HomePresentation.activityLabel(item), recordedDate].joined(separator: " · ")
    }
    private var spokenDescription: String {
        var parts: [String] = [item.title.title, item.label, "Recorded: " + recordedDate]
        if let date = item.watchedDate {
            parts.append("Watch date: " + DetailFormatting.date(date))
        }
        return parts.joined(separator: ", ")
    }
}

struct HomeContinueWatchingRow: View {
    let item: ContinueWatchingItem
    let progressModel: (TVShow) -> TVProgressModel
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(LibraryStore.self) private var library
    @State private var episodeAction = HomeEpisodeAction()
    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) { poster; content }
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { poster; content }
            }
        }
        .padding(.vertical, AppStyle.Spacing.xSmall)
        .onChange(of: item.next?.id) { _, _ in episodeAction.clearError() }
    }
    private var poster: some View { LibraryCachedPoster(url: item.title.posterURL) }
    private var content: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            NavigationLink(value: item.title.destination) {
                Text(item.title.title).font(AppStyle.Typography.mediaTitle)
                    .foregroundStyle(AppStyle.Colors.primaryText).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open details for " + item.title.title)
            .accessibilityIdentifier("home.series." + item.id.value)
            if let percentage = item.progress.percentage {
                Text("\(item.progress.watched) of \(item.progress.eligible) aired episodes watched")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                if item.progress.isUpToDate {
                    Text("Up to date with known aired episodes").font(AppStyle.Typography.caption)
                        .accessibilityIdentifier("home.upToDate." + item.id.value)
                }
                ProgressView(value: Double(percentage), total: 100)
                    .accessibilityLabel(item.title.title + ", known aired regular episode progress")
                    .accessibilityValue("\(item.progress.watched) of \(item.progress.eligible), \(percentage) percent")
                    .accessibilityIdentifier("home.progress")
            } else {
                Text(HomePresentation.watchedCount(item.progress.totalWatched))
                    .accessibilityIdentifier("home.watchedCount." + item.id.value)
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            }
            if let last = item.lastMarked, last.number > 0 {
                Text("Last marked watched: S\(last.seasonNumber) E\(last.number)")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            }
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
                .buttonStyle(AppActionStyle(fillsWidth: true))
                .accessibilityHint("Opens the season. It does not mark the episode watched.")
                .accessibilityIdentifier("home.nextEpisode")
                directAction(for: next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func directAction(for next: TVEpisode) -> some View {
        Text(next.title).font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        Button {
            mark(next)
        } label: {
            Label(markLabel(for: next), systemImage: "checkmark.circle")
        }
        .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
        .disabled(episodeAction.isSaving || library.isWatched(next.id))
        .accessibilityLabel("Mark \(item.title.title), season \(next.seasonNumber), episode \(next.number), \(next.title), watched")
        .accessibilityValue(episodeAction.isSaving ? "Saving" : library.isWatched(next.id) ? "Watched" : "Not watched")
        .accessibilityIdentifier("home.markEpisode." + item.id.value)
        if episodeAction.isSaving { AppLoadingState(title: "Saving progress…") }
        if let error = episodeAction.errorMessage {
            AppErrorMessage(message: error).accessibilityIdentifier("home.episodeError")
            Button("Retry Save") { mark(next) }
                .buttonStyle(AppActionStyle()).accessibilityIdentifier("home.retryEpisode")
        }
    }
    private func markLabel(for next: TVEpisode) -> String {
        if episodeAction.isSaving { return "Saving progress…" }
        if library.isWatched(next.id) { return "Watched" }
        return "Mark S\(next.seasonNumber) E\(next.number) watched"
    }
    private func mark(_ next: TVEpisode) {
        episodeAction.mark(next.id, store: library)
        if episodeAction.errorMessage == nil && library.isWatched(next.id) {
            UIAccessibility.post(notification: .announcement, argument: "\(item.title.title), season \(next.seasonNumber), episode \(next.number) marked watched")
        }
    }
}

@MainActor
@Observable
final class HomeEpisodeAction {
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    func mark(_ episode: EpisodeID, store: LibraryStore, now: Date = .now) {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try store.markNextEpisodeWatched(episode, now: now)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func clearError() { errorMessage = nil }
}

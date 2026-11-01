import Foundation
import Observation

enum LibraryMediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", movies = "Movies", tvShows = "TV Shows"
    var id: Self { self }
}
enum LibraryStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All statuses", watchlist = "Watchlist", watching = "Watching", watched = "Watched"
    var id: Self { self }
    var storedValue: String? {
        switch self { case .all: nil; case .watchlist: "watchlist"; case .watching: "watching"; case .watched: "watched" }
    }
}
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded = "Recently Added", title = "Title A–Z", year = "Release Year", rating = "Personal Rating"
    var id: Self { self }
}
struct LibraryOptions: Equatable {
    var media: LibraryMediaFilter = .all
    var status: LibraryStatusFilter = .all
    var favoritesOnly = false
    var sort: LibrarySort = .recentlyAdded
}
enum LibraryItemRating: Equatable, Sendable {
    case unrated, rated(PersonalRating), invalid
    var value: PersonalRating? { if case .rated(let value) = self { value } else { nil } }
    var rank: Int { switch self { case .rated: 0; case .unrated: 1; case .invalid: 2 } }
    var label: String {
        switch self {
        case .rated(let value): "Your rating: " + value.label
        case .unrated: "Unrated"
        case .invalid: "Personal rating unavailable"
        }
    }
}

struct LibraryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let mediaID: MediaID?
    let title: String
    let normalizedTitle: String
    let year: Int?
    let posterURL: URL?
    let rawStatus: String
    let isFavorite: Bool
    let addedAt: Date
    let rating: LibraryItemRating

    var mediaLabel: String {
        switch mediaID?.kind { case .movie: "Movie"; case .tvShow: "TV Show"; case nil: "Unknown media type" }
    }
    var statusLabel: String {
        switch rawStatus {
        case "watchlist": "Watchlist"; case "watching": "Watching"; case "watched": "Watched"
        case "none": "No viewing status"; default: "Unrecognized viewing status"
        }
    }
    @MainActor
    init(entry: StoredLibraryEntry) {
        id = entry.id; mediaID = entry.mediaID
        let saved = entry.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = saved.isEmpty ? "Saved title — metadata unavailable" : saved
        normalizedTitle = LibraryText.normalize(title)
        year = entry.savedYear.flatMap { $0 > 0 ? $0 : nil }
        posterURL = entry.thumbnailURL
        rawStatus = entry.status; isFavorite = entry.isFavorite; addedAt = entry.addedAt
        do { rating = try entry.validatedRating().map { .rated($0) } ?? .unrated }
        catch { rating = .invalid }
    }
    init(id: UUID, mediaID: MediaID?, title: String, year: Int?, rawStatus: String, isFavorite: Bool,
         addedAt: Date, rating: LibraryItemRating, posterURL: URL? = nil) {
        self.id = id; self.mediaID = mediaID; self.title = title; normalizedTitle = LibraryText.normalize(title)
        self.year = year; self.rawStatus = rawStatus; self.isFavorite = isFavorite
        self.addedAt = addedAt; self.rating = rating; self.posterURL = posterURL
    }
}

enum LibraryText {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

struct LibraryEmptyState: Equatable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class LibraryOrganizationModel {
    var query = "" { didSet { if LibraryText.normalize(query) != LibraryText.normalize(oldValue) { filter() } } }
    var options = LibraryOptions() {
        didSet {
            guard options != oldValue else { return }
            if options.sort != oldValue.sort { sortSource() }
            filter()
        }
    }
    private(set) var sourceReady = false
    private(set) var visible: [LibraryItem] = []
    private(set) var totalCount = 0
    @ObservationIgnored private var source: [LibraryItem] = []
    @ObservationIgnored private var sorted: [LibraryItem] = []
    @ObservationIgnored private var revision: Int?

    var hasFilters: Bool {
        !LibraryText.normalize(query).isEmpty || options.media != .all || options.status != .all || options.favoritesOnly
    }
    var emptyState: LibraryEmptyState {
        if totalCount == 0 {
            return .init(title: "Your library is empty", message: "Find a movie or TV show in Search, then save it from its detail page.")
        }
        if !LibraryText.normalize(query).isEmpty {
            return .init(title: "No saved titles match", message: "Try another title or reset your filters. This search only checks titles already in your Library.")
        }
        if options.favoritesOnly {
            return .init(title: options.media == .all && options.status == .all ? "No favorites yet" : "No favorites match these filters",
                         message: "Favorites can have any viewing status, including no status. Choose All statuses or adjust the media filter.")
        }
        switch options.status {
        case .watchlist: return .init(title: "Your watchlist is empty", message: "Add a title to Watchlist from Details, or change your media filter.")
        case .watching: return .init(title: "No watching series", message: "Watching is normally used for TV shows. Choose All media or TV Shows, or update a series in Details.")
        case .watched: return .init(title: "No watched titles", message: "Mark a saved title Watched from Details, or adjust the media filter.")
        case .all: return .init(title: "No saved titles match", message: "Choose another media type or reset your filters.")
        }
    }

    func replaceEntries(_ entries: [StoredLibraryEntry], revision: Int) {
        guard self.revision != revision else { return }
        self.revision = revision
        replaceItems(entries.map { LibraryItem(entry: $0) })
    }
    /// Pure snapshots also let tests exercise thousands of records without network or repeated SQL writes.
    func replaceItems(_ items: [LibraryItem]) {
        source = items; totalCount = items.count; sourceReady = true
        sortSource(); filter()
    }
    func resetFilters() {
        query = ""
        options = LibraryOptions(sort: options.sort)
    }
    private func filter() {
        let needle = LibraryText.normalize(query)
        visible = sorted.filter { item in
            (options.media == .all || (options.media == .movies && item.mediaID?.kind == .movie)
                || (options.media == .tvShows && item.mediaID?.kind == .tvShow))
                && (options.status.storedValue == nil || item.rawStatus == options.status.storedValue)
                && (!options.favoritesOnly || item.isFavorite)
                && (needle.isEmpty || item.normalizedTitle.contains(needle))
        }
    }
    private func sortSource() {
        sorted = source.sorted { lhs, rhs in
            switch options.sort {
            case .recentlyAdded:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .title: break
            case .year:
                if lhs.year != rhs.year {
                    if let left = lhs.year, let right = rhs.year { return left > right }
                    return lhs.year != nil
                }
            case .rating:
                if lhs.rating.rank != rhs.rating.rank { return lhs.rating.rank < rhs.rating.rank }
                if lhs.rating.value?.halfStarUnits != rhs.rating.value?.halfStarUnits {
                    return (lhs.rating.value?.halfStarUnits ?? 0) > (rhs.rating.value?.halfStarUnits ?? 0)
                }
            }
            if lhs.normalizedTitle != rhs.normalizedTitle { return lhs.normalizedTitle < rhs.normalizedTitle }
            if lhs.mediaID?.kind.rawValue != rhs.mediaID?.kind.rawValue { return (lhs.mediaID?.kind.rawValue ?? "~") < (rhs.mediaID?.kind.rawValue ?? "~") }
            if lhs.mediaID?.value != rhs.mediaID?.value { return (lhs.mediaID?.value ?? "~") < (rhs.mediaID?.value ?? "~") }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

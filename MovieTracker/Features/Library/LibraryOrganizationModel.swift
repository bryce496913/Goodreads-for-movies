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
struct LibraryOptions: Equatable, Sendable {
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
        self = LibraryItemInput(entry: entry).item()
    }
    init(id: UUID, mediaID: MediaID?, title: String, year: Int?, rawStatus: String, isFavorite: Bool,
         addedAt: Date, rating: LibraryItemRating, posterURL: URL? = nil) {
        self.id = id; self.mediaID = mediaID; self.title = title; normalizedTitle = LibraryText.normalize(title)
        self.year = year; self.rawStatus = rawStatus; self.isFavorite = isFavorite
        self.addedAt = addedAt; self.rating = rating; self.posterURL = posterURL
    }
}

/// Capture on the context actor; normalize text and validate ratings on the worker.
struct LibraryItemInput: Sendable {
    let id: UUID
    let mediaID: MediaID?
    let title: String?
    let mediaData: Data?
    let year: Int?
    let posterURL: URL?
    let status: String
    let favorite: Bool
    let addedAt: Date
    let ratingUnits: Int?
    let legacyRating: Double?

    @MainActor init(entry: StoredLibraryEntry) {
        id = entry.id; mediaID = entry.mediaID; title = entry.savedTitle; mediaData = entry.snapshotData
        year = entry.savedYear; posterURL = entry.thumbnailURL; status = entry.status
        favorite = entry.isFavorite; addedAt = entry.addedAt
        ratingUnits = entry.ratingHalfStarUnits; legacyRating = entry.rating
    }
    func item() -> LibraryItem {
        let decoded = title?.isEmpty == false ? nil : mediaData.flatMap { try? JSONDecoder().decode(MediaSearchResult.self, from: $0) }
        let fallback = decoded.flatMap { SearchItem($0).id == mediaID ? SearchItem($0).title : nil }
            ?? mediaID.map(MetadataPolicy.placeholder) ?? "Saved title — metadata unavailable"
        let saved = title?.isEmpty == false ? title ?? fallback : fallback
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        let rating: LibraryItemRating
        do {
            let value = try ratingUnits.map { try PersonalRating(halfStarUnits: $0) }
                ?? legacyRating.flatMap { try PersonalRating.fromLegacyStars($0) }
            rating = value.map { .rated($0) } ?? .unrated
        } catch { rating = .invalid }
        return LibraryItem(id: id, mediaID: mediaID, title: trimmed.isEmpty ? "Saved title — metadata unavailable" : trimmed,
            year: year.flatMap { $0 > 0 ? $0 : nil }, rawStatus: status, isFavorite: favorite,
            addedAt: addedAt, rating: rating, posterURL: posterURL)
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
    var query = "" { didSet { if LibraryText.normalize(query) != LibraryText.normalize(oldValue) { schedule() } } }
    var options = LibraryOptions() {
        didSet {
            guard options != oldValue else { return }
            schedule()
        }
    }
    private(set) var sourceReady = false
    private(set) var visible: [LibraryItem] = []
    private(set) var totalCount = 0
    @ObservationIgnored private var source: [LibraryItem] = []
    @ObservationIgnored private var sorted: [LibraryItem] = []
    @ObservationIgnored private var sortedBy: LibrarySort?
    @ObservationIgnored private var pendingInput: [LibraryItemInput]?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<LibraryProjection.Result, Error>?
    private(set) var isUpdating = false
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
        pendingInput = entries.map { LibraryItemInput(entry: $0) }
        sortedBy = nil
        totalCount = entries.count
        schedule()
    }
    /// Pure snapshots also let tests exercise thousands of records without network or repeated SQL writes.
    func replaceItems(_ items: [LibraryItem]) {
        pendingInput = nil; source = items; totalCount = items.count; sortedBy = nil
        schedule()
    }
    func resetFilters() {
        query = ""
        options = LibraryOptions(sort: options.sort)
    }
    /// Await the newest scheduled work, including replacements that arrive while suspended.
    func waitForUpdates() async {
        while let current = work {
            let token = generation
            await current.value
            if token == generation { return }
        }
    }
    func cancelUpdates() {
        worker?.cancel(); work?.cancel(); generation = UUID()
        worker = nil; work = nil; isUpdating = false; revision = nil
    }
    private func schedule() {
        worker?.cancel(); work?.cancel()
        generation = UUID(); let token = generation
        let input = pendingInput, source = source, ordered = sortedBy == options.sort ? sorted : nil
        let query = query, options = options
        isUpdating = true
        let worker = Task.detached(priority: .userInitiated) {
            let values: [LibraryItem]
            if let input {
                values = try input.map { try Task.checkCancellation(); return $0.item() }
            } else { values = source }
            return try LibraryProjection.project(source: values, sorted: ordered, query: query, options: options)
        }
        self.worker = worker
        work = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.source = result.source; self.sorted = result.sorted; self.visible = result.visible
                self.sortedBy = options.sort; self.pendingInput = nil; self.sourceReady = true
            } catch { /* Replacement/cancellation retains the previous consistent projection. */ }
            guard let self, self.generation == token else { return }
            self.isUpdating = false; self.worker = nil; self.work = nil
        }
    }
}

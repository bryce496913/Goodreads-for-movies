import Foundation
import SwiftData
import XCTest
@testable import MovieTracker

/// Test-only content. Historical schema definitions themselves are frozen in production.
enum MigrationFixtureShape: CaseIterable {
    case foundation, snapshots, ratings, diary, tvProgress, current
    var version: any VersionedSchema.Type {
        switch self {
        case .foundation: LibrarySchemaFoundation.self
        case .snapshots: LibrarySchemaSnapshots.self
        case .ratings: LibrarySchemaRatings.self
        case .diary: LibrarySchemaDiary.self
        case .tvProgress: LibrarySchemaTVProgress.self
        case .current: LibrarySchemaV1.self
        }
    }
    var hasSnapshots: Bool { self != .foundation }
    var hasUnits: Bool { ![Self.foundation, .snapshots].contains(self) }
    var hasDiary: Bool { [.diary, .tvProgress, .current].contains(self) }
    var hasEpisodes: Bool { [.tvProgress, .current].contains(self) }
}

private protocol LibraryFixtureRow: PersistentModel {
    init(entry: UserLibraryEntry)
    var rating: Double? { get set }
}
private protocol SnapshotFixtureRow: LibraryFixtureRow {
    var savedTitle: String? { get set }
    var savedYear: Int? { get set }
    var savedPosterReference: String? { get set }
    var savedPosterURL: String? { get set }
    var snapshotData: Data? { get set }
}
extension LibrarySchemaFoundation.StoredLibraryEntry: LibraryFixtureRow {}
extension LibrarySchemaSnapshots.StoredLibraryEntry: SnapshotFixtureRow {}
extension LibrarySchemaRatings.StoredLibraryEntry: SnapshotFixtureRow {}
extension StoredLibraryEntry: SnapshotFixtureRow {}

@MainActor
enum MigrationFixtures {
    static let date = Date(timeIntervalSince1970: 1_704_067_200)
    static let movieID = MediaID(kind: .movie, value: "tmdb:42")
    static let tvID = MediaID(kind: .tvShow, value: "tmdb:42")
    static let otherID = MediaID(kind: .movie, value: "other:42")
    static func uuid(_ number: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(number)))
    }
    static var show: TVShow {
        TVShow(id: tvID.value, title: "Saved TV", seasons: [TVSeasonSummary(number: 1, providerID: "tmdb:season", name: "Season 1", episodeCount: 2)])
    }
    static var episodes: [TVEpisode] {
        (1...2).map { TVEpisode(id: EpisodeID(seriesID: tvID, providerValue: "tmdb:episode:\($0)"), seasonNumber: 1,
            number: $0, title: "Saved episode \($0)", airDate: date, overview: "Saved episode synopsis", runtimeMinutes: 45) }
    }
    static var movie: MediaSearchResult { .movie(Movie(id: movieID.value, title: "Saved Movie", overview: "Saved synopsis")) }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func write(_ shape: MigrationFixtureShape, at url: URL, versioned: Bool = false) throws {
        try autoreleasepool {
            // Unversioned is deliberate: this reproduces how PR001–012 opened their stores.
            let schema = versioned ? Schema(versionedSchema: shape.version) : Schema(shape.version.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = container.mainContext
            context.autosaveEnabled = false
            switch shape {
            case .foundation: try insertLibrary(LibrarySchemaFoundation.StoredLibraryEntry.self, into: context)
            case .snapshots: try insertLibrary(LibrarySchemaSnapshots.StoredLibraryEntry.self, into: context)
            case .ratings, .diary, .tvProgress: try insertLibrary(LibrarySchemaRatings.StoredLibraryEntry.self, into: context)
            case .current: try insertLibrary(StoredLibraryEntry.self, into: context)
            }
            if shape.hasDiary {
                context.insert(try StoredViewingEvent(id: uuid(10), media: movie, watchedDate: date, recordedAt: date.addingTimeInterval(10)))
                context.insert(try StoredViewingEvent(id: uuid(11), media: movie, watchedDate: nil, recordedAt: date.addingTimeInterval(20)))
                let review = try StoredPersonalReview(id: uuid(20), media: movie, text: "Private review preserved exactly\nSecond line", createdAt: date,
                                                     viewingEventID: uuid(10))
                review.editedAt = date.addingTimeInterval(30); context.insert(review)
                context.insert(try StoredPersonalReview(id: uuid(21), media: .tvShow(show), text: "Independent series review", createdAt: date,
                                                       viewingEventID: nil, isLegacyImport: true))
            }
            if shape.hasEpisodes {
                let season = try StoredTVSeason(show: show, summary: try XCTUnwrap(show.seasons?.first))
                season.id = uuid(30); season.listingLoaded = true; season.refreshedAt = date
                season.episodesData = try encode(episodes); season.listedIDsData = try encode(episodes.map(\.id))
                context.insert(season)
                for (index, episode) in episodes.enumerated() {
                    let progress = try StoredEpisodeProgress(episode: episode, watched: index == 0, now: date)
                    progress.id = uuid(40 + index); context.insert(progress)
                }
            }
            try context.save()
        }
    }
    private static func insertLibrary<Row: LibraryFixtureRow>(_ type: Row.Type, into context: ModelContext) throws {
        for (index, id) in [movieID, tvID, otherID].enumerated() {
            let entry = UserLibraryEntry(id: uuid(index + 1), mediaID: id, status: id.kind == .movie ? .watched : .watching,
                isFavorite: true, rating: try PersonalRating(halfStarUnits: 9), review: "Reserved legacy review \(index)",
                addedAt: date, updatedAt: date.addingTimeInterval(5))
            let row = Row(entry: entry)
            if let snapshots = row as? any SnapshotFixtureRow {
                snapshots.savedTitle = id.kind == .movie ? "Saved Movie" : "Saved TV"
                snapshots.savedYear = 2024; snapshots.savedPosterReference = "/poster.jpg"
                snapshots.savedPosterURL = "https://image.tmdb.org/t/p/w185/poster.jpg"
                let media: MediaSearchResult = id.kind == .movie ? .movie(Movie(id: id.value, title: "Saved Movie", overview: "Saved synopsis")) : .tvShow(show)
                snapshots.snapshotData = try encode(media)
            }
            if let current = row as? StoredLibraryEntry { current.ratingUpdatedAt = date.addingTimeInterval(40) }
            context.insert(row)
        }
    }
}

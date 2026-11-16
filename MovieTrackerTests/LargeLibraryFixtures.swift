import Foundation
import SwiftData
@testable import MovieTracker

/// Test-only deterministic values. No launch argument, production seeding or network access.
enum LargeLibraryFixtures {
    static let now = Date(timeIntervalSince1970: 1_767_225_600)
    static let aired = Date(timeIntervalSince1970: 1_577_836_800)
    static func uuid(_ value: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                    UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)))
    }
    static func mediaID(_ index: Int) -> MediaID {
        MediaID(kind: index.isMultiple(of: 2) ? .tvShow : .movie, value: "fixture:\(index)")
    }
    static func items(_ count: Int) throws -> [LibraryItem] {
        try (0..<count).map { i in
            LibraryItem(id: uuid(i), mediaID: mediaID(i), title: (i.isMultiple(of: 4) ? "Café " : "Title ") + String(i % 50),
                year: i.isMultiple(of: 9) ? nil : 1980 + i % 40,
                rawStatus: i.isMultiple(of: 6) ? "watching" : (i.isMultiple(of: 3) ? "watched" : "watchlist"),
                isFavorite: i.isMultiple(of: 7), addedAt: aired.addingTimeInterval(Double(i % 50)),
                rating: i.isMultiple(of: 5) ? .unrated : .rated(try PersonalRating(halfStarUnits: i % 10 + 1)))
        }
    }
    static func episode(_ index: Int) -> TVEpisode {
        TVEpisode(id: EpisodeID(seriesID: mediaID((index / 100) * 2), providerValue: "fixture:episode:\(index)"),
            seasonNumber: 1, number: index % 100 + 1, title: "Episode \(index)", airDate: aired,
            overview: "", runtimeMinutes: nil)
    }
    static func dashboard(titles: Int = 5_000, episodes: Int = 10_000, events: Int = 5_000) throws -> DashboardInput {
        let rows = try items(titles)
        return DashboardInput(titles: rows.map {
            DashboardInput.Title(recordID: $0.id, mediaID: $0.mediaID, title: $0.title, year: $0.year,
                posterURL: nil, status: $0.rawStatus, favorite: $0.isFavorite, addedAt: $0.addedAt,
                updatedAt: $0.addedAt, ratingUnits: $0.rating.value?.halfStarUnits, legacyRating: nil,
                ratingUpdatedAt: nil, legacyReview: nil, mediaData: nil)
        }, viewings: (0..<events).map { i in
            DashboardInput.Viewing(id: uuid(i), mediaID: mediaID(i % max(1, min(titles, 100))), title: "Saved title",
                watchedDate: i.isMultiple(of: 5) ? nil : aired.addingTimeInterval(Double(i % 365) * 86_400),
                recordedAt: now.addingTimeInterval(Double(i)), mediaData: nil)
        }, progress: try (0..<episodes).map { i in
            let value = episode(i)
            return DashboardInput.Progress(id: uuid(i), episodeID: value.id, season: value.seasonNumber,
                watched: i.isMultiple(of: 2), watchedAt: i.isMultiple(of: 2) ? now : nil,
                episodeData: try JSONEncoder().encode(value))
        })
    }
    @MainActor
    static func store(titles: Int = 5_000, episodes: Int = 10_000, events: Int = 5_000) throws -> LibraryStore {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        for item in try items(titles) {
            let id = item.mediaID!
            let row = StoredLibraryEntry(entry: UserLibraryEntry(id: item.id, mediaID: id, status: nil,
                addedAt: item.addedAt, updatedAt: item.addedAt))
            row.status = item.rawStatus; row.savedTitle = item.title; row.savedYear = item.year
            row.isFavorite = item.isFavorite; row.ratingHalfStarUnits = item.rating.value?.halfStarUnits
            context.insert(row)
        }
        for i in 0..<events {
            let id = mediaID(i % max(1, min(titles, 100)))
            let media: MediaSearchResult = id.kind == .movie ? .movie(Movie(id: id.value, title: "Saved title"))
                : .tvShow(TVShow(id: id.value, title: "Saved title"))
            context.insert(try StoredViewingEvent(id: uuid(i), media: media,
                watchedDate: i.isMultiple(of: 5) ? nil : aired.addingTimeInterval(Double(i % 365) * 86_400),
                recordedAt: now.addingTimeInterval(Double(i))))
        }
        for i in 0..<episodes {
            let row = try StoredEpisodeProgress(episode: episode(i), watched: i.isMultiple(of: 2), now: now)
            row.id = uuid(i); context.insert(row)
        }
        try context.save()
        return LibraryStore(container: container)
    }
    @MainActor static func collectionsStore() throws -> LibraryStore {
        let store = try Self.store(titles: 5_000, episodes: 0, events: 0)
        try store.writeTransaction { context in
            for list in 0..<500 {
                let id = uuid(100_000 + list)
                context.insert(StoredCollection(id: id, name: "Collection \(list)", createdAt: now, updatedAt: now))
                for position in 0..<10 {
                    let index = list * 10 + position
                    context.insert(StoredCollectionMembership(id: uuid(200_000 + index), collectionID: id,
                        mediaID: mediaID(index), position: position, addedAt: now))
                }
            }
        }
        return store
    }
    static func discoveryInputs(_ count: Int = 5_000) throws -> [DiscoveryInput] {
        try (0..<count).map { index in
            let id = mediaID(index), genres = [MediaGenre(id: "fixture:drama", name: "Drama")]
            let date: Date? = index.isMultiple(of: 5) ? nil : aired
            let media: MediaSearchResult = id.kind == .movie
                ? .movie(Movie(id: id.value, title: "Title \(index)", releaseDate: date, runtimeMinutes: 90, genres: genres))
                : .tvShow(TVShow(id: id.value, title: "Title \(index)", firstAirDate: date, episodeRuntimeMinutes: 42, genres: genres))
            return DiscoveryInput(id: id, library: nil, payloads: [try JSONEncoder().encode(media)], seriesPayloads: [])
        }
    }

}

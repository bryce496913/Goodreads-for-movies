import SwiftData
@testable import MovieTracker

enum BackupFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 788_918_400.1234567)
    static let movieID = MediaID(kind: .movie, value: "tmdb:72")
    static let showID = MediaID(kind: .tvShow, value: "tmdb:72")
    static let reviewID = LargeLibraryFixtures.uuid(30)
    static let eventID = LargeLibraryFixtures.uuid(40)
    static let repeatID = LargeLibraryFixtures.uuid(41)
    static let text = "Personal review 🌕\nSecond line."
    static let episode = TVEpisode(id: EpisodeID(seriesID: showID, providerValue: "tmdb:episode:1"), seasonNumber: 1,
        number: 1, title: "PROVIDER_EPISODE_NOT_EXPORTED", airDate: now.addingTimeInterval(-86_400),
        overview: "PROVIDER_SYNOPSIS_NOT_EXPORTED", runtimeMinutes: 42, metadataRetrievedAt: now)
    @MainActor static func store(at url: URL? = nil, failSave: Bool = false) throws -> LibraryStore {
        let container = try url.map { try PersistenceController.makeContainer(at: $0) } ?? PersistenceController.makeContainer(inMemory: true)
        return LibraryStore(container: container, clock: { now }, save: { context in
            if failSave { throw LibraryStoreError.saveFailed }; try context.save()
        })
    }
    @MainActor static func populated() throws -> LibraryStore {
        let store = try Self.store()
        let movie = MediaSearchResult.movie(Movie(id: movieID.value, title: "PROVIDER_TITLE_NOT_EXPORTED",
            overview: "PROVIDER_SYNOPSIS_NOT_EXPORTED", posterReference: "/PROVIDER_POSTER_NOT_EXPORTED.png", metadataRetrievedAt: now))
        let show = TVShow(id: showID.value, title: "PROVIDER_TV_NOT_EXPORTED", seasons: [TVSeasonSummary(number: 1, providerID: nil,
            name: "PROVIDER_SEASON_NOT_EXPORTED", episodeCount: 1)], metadataRetrievedAt: now)
        try store.setStatus(.watched, media: movie)
        try store.setFavorite(true, media: movie)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 7), media: movie)
        try store.saveViewingEvent(id: eventID, media: movie, watchedDate: now, now: now)
        try store.saveViewingEvent(id: repeatID, media: movie, watchedDate: nil, now: now.addingTimeInterval(100))
        try store.saveReview(id: reviewID, media: movie, text: text, eventID: eventID, now: now)
        try store.cacheSeasonCatalog(show: show)
        try store.setEpisodeWatched(true, episode: episode, show: show, now: now)
        try store.writeTransaction { _ in store.entry(for: movieID)?.review = "Retained legacy note" }
        return store
    }
    static func library(_ old: PersonalBackup.Library, status: LibraryStatus? = .watchlist, units: Int? = 10,
                        id: UUID? = nil, mediaID: MediaID? = nil) -> PersonalBackup.Library {
        PersonalBackup.Library(id: id ?? old.id, mediaID: mediaID ?? old.mediaID, status: status, favorite: !old.favorite,
            ratingHalfStarUnits: units, ratingUpdatedAt: old.ratingUpdatedAt, legacyReview: old.legacyReview,
            addedAt: old.addedAt, updatedAt: old.updatedAt)
    }
    static func tempFile(_ bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try bytes.write(to: url, options: .atomic); return url
    }
    @MainActor static func plan(_ backup: PersonalBackup, into store: LibraryStore) throws -> BackupMergePlan {
        try BackupMergePlanner.prepare(backup, local: store.capturePersonalBackup(at: now, includeAllAnchors: true), revision: store.revision)
    }
}

import SwiftData
import XCTest
@testable import MovieTracker

final class LibraryOrganizationTests: XCTestCase {
    @MainActor
    func testMovieAndTVFiltersOnFiveThousandRecords() async throws {
        let model = try makeModel()
        model.options.media = .movies
        XCTAssertEqual(model.visible.count, 2_500)
        XCTAssertTrue(model.visible.allSatisfy { $0.mediaID?.kind == .movie })
        model.options.media = .tvShows
        XCTAssertEqual(model.visible.count, 2_500)
        XCTAssertTrue(model.visible.allSatisfy { $0.mediaID?.kind == .tvShow })
    }

    @MainActor
    func testStatusFilterAndCombinedFavoritesQueryUseAND() async throws {
        let model = try makeModel()
        model.options.status = .watching
        XCTAssertEqual(model.visible.count, 834) // Multiples of six in 0..<5000.
        model.options.media = .tvShows
        model.options.favoritesOnly = true
        model.query = "  CAFE  "
        XCTAssertEqual(model.visible.count, 60) // Multiples of 84.
        XCTAssertTrue(model.visible.allSatisfy { $0.rawStatus == "watching" && $0.isFavorite })
        model.options.media = .movies
        XCTAssertTrue(model.visible.isEmpty)
    }

    @MainActor
    func testFavoritesIncludeWatchedAndNoStatusTitles() async throws {
        let model = LibraryOrganizationModel()
        model.replaceItems([
            item(1, title: "Movie", kind: .movie, status: "watched", favorite: true),
            item(2, title: "TV", kind: .tvShow, status: "none", favorite: true),
            item(3, title: "Other", favorite: false)
        ])
        model.options.favoritesOnly = true
        XCTAssertEqual(model.visible.count, 2)
        XCTAssertEqual(Set(model.visible.map(\.rawStatus)), ["watched", "none"])
    }

    @MainActor
    func testTitleOrderingIsFoldedAndDeterministicAcrossInputOrder() async throws {
        let dataset = try data()
        let model = LibraryOrganizationModel()
        model.replaceItems(dataset)
        model.options.sort = .title
        let first = model.visible.map(\.id)
        let keys = model.visible.map(\.normalizedTitle)
        XCTAssertEqual(keys, keys.sorted())
        model.replaceItems(Array(dataset.reversed()))
        XCTAssertEqual(model.visible.map(\.id), first)
    }

    @MainActor
    func testYearSortIsNewestFirstWithUnknownLast() async throws {
        let model = LibraryOrganizationModel()
        model.replaceItems([item(1, title: "Unknown", year: nil), item(2, title: "Older", year: 1990), item(3, title: "Newer", year: 2024)])
        model.options.sort = .year
        XCTAssertEqual(model.visible.map(\.title), ["Newer", "Older", "Unknown"])
        XCTAssertNil(model.visible.last?.year)
    }

    @MainActor
    func testRatingSortValidDescendingThenUnratedThenInvalid() async throws {
        let model = LibraryOrganizationModel()
        model.replaceItems([
            item(1, title: "Unrated"), item(2, title: "Invalid", rating: .invalid),
            item(3, title: "Half", rating: .rated(try PersonalRating(halfStarUnits: 1))),
            item(4, title: "Five", rating: .rated(try PersonalRating(halfStarUnits: 10)))
        ])
        model.options.sort = .rating
        XCTAssertEqual(model.visible.map(\.title), ["Five", "Half", "Unrated", "Invalid"])
    }

    @MainActor
    func testRecentlyAddedIgnoresUpdatedDatesAndTiesUseIdentity() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let first = StoredLibraryEntry(entry: UserLibraryEntry(id: uuid(1), mediaID: MediaID(kind: .movie, value: "p:1"),
            addedAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 9_000)))
        first.savedTitle = "Older"
        let second = StoredLibraryEntry(entry: UserLibraryEntry(id: uuid(2), mediaID: MediaID(kind: .movie, value: "p:2"),
            addedAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 2_000)))
        second.savedTitle = "Newer"
        container.mainContext.insert(first); container.mainContext.insert(second)
        try container.mainContext.save()
        let model = LibraryOrganizationModel()
        model.replaceItems([LibraryItem(entry: first), LibraryItem(entry: second)])
        XCTAssertEqual(model.visible.map(\.title), ["Newer", "Older"])
        let same = [item(3, title: "Same"), item(1, title: "Same"), item(2, title: "Same")]
        model.replaceItems(same)
        let order = model.visible.map(\.id)
        model.replaceItems(Array(same.reversed()))
        XCTAssertEqual(model.visible.map(\.id), order)
    }

    @MainActor
    func testDiacriticCaseWhitespaceSearchAndClear() async throws {
        let model = try makeModel()
        model.query = "  CAFÉ \n"
        XCTAssertEqual(model.visible.count, 1_250)
        let ids = model.visible.map(\.id)
        model.query = "cafe"
        XCTAssertEqual(model.visible.map(\.id), ids)
        model.query = "not in the saved titles"
        XCTAssertTrue(model.visible.isEmpty)
        XCTAssertEqual(model.emptyState.title, "No saved titles match")
        model.query = ""
        XCTAssertEqual(model.visible.count, 5_000)
    }

    @MainActor
    func testEmptyStatesAndResetFiltersPreserveSort() async throws {
        let model = LibraryOrganizationModel()
        XCTAssertEqual(model.emptyState.title, "Your library is empty")
        model.replaceItems([item(1, title: "Only title", status: "none")])
        model.options.status = .watchlist
        XCTAssertEqual(model.emptyState.title, "Your watchlist is empty")
        model.options.status = .watching
        XCTAssertEqual(model.emptyState.title, "No watching series")
        model.options.status = .watched
        XCTAssertEqual(model.emptyState.title, "No watched titles")
        model.options.status = .all
        model.options.favoritesOnly = true
        XCTAssertEqual(model.emptyState.title, "No favorites yet")
        model.options.sort = .rating
        model.query = "missing"
        model.resetFilters()
        XCTAssertFalse(model.hasFilters)
        XCTAssertEqual(model.options.sort, .rating)
        XCTAssertEqual(model.visible.count, 1)
    }

    @MainActor
    func testLegacyRatingProjectionAndFilteringDoNotMutateSavedData() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let record = StoredLibraryEntry(entry: UserLibraryEntry(mediaID: MediaID(kind: .movie, value: "p:legacy")))
        record.savedTitle = "Résumé"; record.rating = 4.5
        record.savedYear = nil
        container.mainContext.insert(record); try container.mainContext.save()
        let store = LibraryStore(container: container)
        let model = LibraryOrganizationModel()
        model.replaceEntries(store.entries, revision: store.revision)
        XCTAssertEqual(model.visible.first?.rating.value?.halfStarUnits, 9)
        let revision = store.revision
        model.options.sort = .rating; model.query = "resume"; model.options.favoritesOnly = true
        XCTAssertTrue(model.visible.isEmpty)
        XCTAssertNil(record.ratingHalfStarUnits)
        XCTAssertEqual(record.rating, 4.5)
        XCTAssertEqual(record.status, "watchlist")
        XCTAssertNil(record.savedYear)
        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertEqual(store.revision, revision)
    }

    @MainActor
    func testCommittedStatusAndFavoriteChangesUpdateActiveFilter() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = LibraryStore(container: container)
        let media = MediaSearchResult.movie(Movie(id: "p:1", title: "Movie"))
        try store.setStatus(.watchlist, media: media)
        let model = LibraryOrganizationModel()
        model.replaceEntries(store.entries, revision: store.revision)
        model.options.status = .watchlist
        XCTAssertEqual(model.visible.count, 1)
        try store.setStatus(.watched, media: media)
        model.replaceEntries(store.entries, revision: store.revision)
        XCTAssertTrue(model.visible.isEmpty)
        model.options.status = .all; model.options.favoritesOnly = true
        try store.setFavorite(true, for: SearchItem(media).id)
        model.replaceEntries(store.entries, revision: store.revision)
        XCTAssertEqual(model.visible.count, 1)
        try store.setFavorite(false, for: SearchItem(media).id)
        model.replaceEntries(store.entries, revision: store.revision)
        XCTAssertTrue(model.visible.isEmpty)
    }

    @MainActor
    func testQuickFavoriteSurvivesReopenWithoutReplacingMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Library.store")
        let media = MediaSearchResult.movie(Movie(id: "p:1", title: "Offline title"))
        try autoreleasepool {
            let store = LibraryStore(container: try PersistenceController.makeContainer(at: url))
            try store.setStatus(.watched, media: media)
            let data = store.entries.first?.snapshotData
            try store.setFavorite(true, for: SearchItem(media).id)
            XCTAssertEqual(store.entries.first?.snapshotData, data)
        }
        let reopened = LibraryStore(container: try PersistenceController.makeContainer(at: url))
        XCTAssertTrue(reopened.entries.first?.isFavorite == true)
        XCTAssertEqual(reopened.entries.first?.status, "watched")
        XCTAssertEqual(reopened.entries.first?.displayTitle, "Offline title")
    }

    @MainActor
    func testEqualRatingsAndYearsRemainStableAcrossReorderedSource() async throws {
        let model = try makeModel()
        model.options.sort = .rating
        let ratingOrder = model.visible.map(\.id)
        model.replaceItems(Array(try data().reversed()))
        XCTAssertEqual(model.visible.map(\.id), ratingOrder)
        model.options.sort = .year
        let yearOrder = model.visible.map(\.id)
        model.replaceItems(try data())
        XCTAssertEqual(model.visible.map(\.id), yearOrder)
    }

    @MainActor
    func testQuickFavoriteSaveFailureRestoresPreviousState() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let media = MediaSearchResult.movie(Movie(id: "p:1", title: "Movie"))
        let good = LibraryStore(container: container)
        try good.setStatus(.watched, media: media)
        let failing = LibraryStore(container: container, save: { _ in throw LibraryStoreError.saveFailed })
        XCTAssertThrowsError(try failing.setFavorite(true, for: SearchItem(media).id))
        XCTAssertFalse(failing.entries.first?.isFavorite == true)
        XCTAssertEqual(failing.entries.first?.status, "watched")
    }

    @MainActor
    private func makeModel() throws -> LibraryOrganizationModel {
        let model = LibraryOrganizationModel(); model.replaceItems(try data()); return model
    }
    private func data() throws -> [LibraryItem] {
        try (0..<5_000).map { index in
            let kind: MediaID.Kind = index.isMultiple(of: 2) ? .tvShow : .movie
            let status = index.isMultiple(of: 6) ? "watching" : (index.isMultiple(of: 3) ? "watched" : "watchlist")
            let titles = ["Café", "Alpha", "Beta", "Same Title"]
            let rating: LibraryItemRating = index.isMultiple(of: 5) ? .unrated : .rated(try PersonalRating(halfStarUnits: index % 10 + 1))
            return LibraryItem(id: uuid(index), mediaID: MediaID(kind: kind, value: "fixture:\(index)"), title: titles[index % 4],
                year: index.isMultiple(of: 9) ? nil : 1980 + index % 40, rawStatus: status, isFavorite: index.isMultiple(of: 7),
                addedAt: Date(timeIntervalSince1970: 1_577_836_800 + Double(index % 50)), rating: rating)
        }
    }
    private func item(_ number: Int, title: String, kind: MediaID.Kind = .movie, year: Int? = nil, status: String = "none",
                      favorite: Bool = false, rating: LibraryItemRating = .unrated) -> LibraryItem {
        LibraryItem(id: uuid(number), mediaID: MediaID(kind: kind, value: "fixture:\(number)"), title: title, year: year,
                    rawStatus: status, isFavorite: favorite, addedAt: Date(timeIntervalSince1970: 0), rating: rating)
    }
    private func uuid(_ number: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)))
    }
}

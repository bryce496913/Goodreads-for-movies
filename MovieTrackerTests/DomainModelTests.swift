import XCTest
@testable import MovieTracker

final class DomainModelTests: XCTestCase {
    func testMovieInitialization() {
        let date = Date(timeIntervalSince1970: 1_000)
        let movie = Movie(
            id: "42", title: "A Movie", overview: "An overview", releaseDate: date,
            posterReference: "local-poster", genreIDs: ["drama"]
        )
        XCTAssertEqual(movie.id, MediaID(kind: .movie, value: "42"))
        XCTAssertEqual(movie.title, "A Movie")
        XCTAssertEqual(movie.overview, "An overview")
        XCTAssertEqual(movie.releaseDate, date)
        XCTAssertEqual(movie.posterReference, "local-poster")
        XCTAssertEqual(movie.genreIDs, ["drama"])
    }

    func testTVShowInitializationAndUnknownSeasonCount() {
        let date = Date(timeIntervalSince1970: 2_000)
        let show = TVShow(
            id: "42", title: "A Show", overview: "A series", firstAirDate: date,
            posterReference: "show-poster", genreIDs: ["comedy"], seasonCount: 3
        )
        XCTAssertEqual(show.id.kind, .tvShow)
        XCTAssertEqual(show.title, "A Show")
        XCTAssertEqual(show.overview, "A series")
        XCTAssertEqual(show.firstAirDate, date)
        XCTAssertEqual(show.posterReference, "show-poster")
        XCTAssertEqual(show.genreIDs, ["comedy"])
        XCTAssertEqual(show.seasonCount, 3)
        XCTAssertNil(TVShow(id: "unknown", title: "Unknown").seasonCount)
    }

    func testMovieAndTVIdentifiersDoNotCollide() throws {
        let movie = Movie(id: "42", title: "A Movie")
        let show = TVShow(id: "42", title: "A Show")
        XCTAssertNotEqual(movie.id, show.id)
        XCTAssertEqual(Set([movie.id, show.id]).count, 2)
        let data = try JSONEncoder().encode(show.id)
        XCTAssertEqual(try JSONDecoder().decode(MediaID.self, from: data), show.id)
    }

    func testLibraryStatusesAndIndependentFavorites() {
        XCTAssertEqual(Set(LibraryStatus.allCases), [.watchlist, .watching, .watched])
        let added = Date(timeIntervalSince1970: 3_000)
        let entry = UserLibraryEntry(mediaID: MediaID(kind: .movie, value: "42"), addedAt: added)
        XCTAssertEqual(entry.status, .watchlist)
        XCTAssertFalse(entry.isFavorite)
        XCTAssertNil(entry.rating)
        XCTAssertNil(entry.review)
        XCTAssertEqual(entry.addedAt, entry.updatedAt)
        var watched = entry
        watched.status = .watched
        watched.isFavorite = true
        XCTAssertEqual(watched.status, .watched)
        XCTAssertTrue(watched.isFavorite)
    }
}

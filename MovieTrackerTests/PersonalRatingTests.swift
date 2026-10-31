import XCTest
@testable import MovieTracker

final class PersonalRatingTests: XCTestCase {
    func testEveryValidHalfStarIncrementAndEncoding() throws {
        XCTAssertEqual(PersonalRating.allValues.count, 10)
        for units in 1...10 {
            let value = try PersonalRating(halfStarUnits: units)
            XCTAssertEqual(value.stars, Double(units) / 2)
            XCTAssertEqual(try JSONDecoder().decode(PersonalRating.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testInvalidUnitsAndInvalidEncodedValuesAreRejected() {
        for units in [Int.min, -1, 0, 11, Int.max] {
            XCTAssertThrowsError(try PersonalRating(halfStarUnits: units))
            XCTAssertThrowsError(try JSONDecoder().decode(PersonalRating.self, from: Data(String(units).utf8)))
        }
    }

    func testLegacyStarsAreNeverRoundedAndZeroIsUnrated() throws {
        XCTAssertNil(try PersonalRating.fromLegacyStars(0))
        XCTAssertEqual(try PersonalRating.fromLegacyStars(4.5)?.halfStarUnits, 9)
        for invalid in [-1.0, 0.1, 3.3, 5.5, .nan, .infinity] {
            XCTAssertThrowsError(try PersonalRating.fromLegacyStars(invalid))
        }
    }
}

import XCTest
@testable import MovieTracker

final class MetadataCredentialTests: XCTestCase {
    @MainActor func testIsolatedKeychainRoundTripUpdateAndRemoval() throws {
        let store = KeychainMetadataCredentialStorage(service: "MovieTracker.UnitTests." + UUID().uuidString)
        defer { try? store.remove() }
        XCTAssertNil(try store.read())
        try store.save("  nonsecret-fixture-one  ")
        XCTAssertEqual(try store.read(), "nonsecret-fixture-one")
        try store.save("nonsecret-fixture-two")
        XCTAssertEqual(try store.read(), "nonsecret-fixture-two")
        try store.remove(); try store.remove()
        XCTAssertNil(try store.read())
    }
    @MainActor func testInvalidCredentialDoesNotReplaceSavedValue() throws {
        let store = KeychainMetadataCredentialStorage(service: "MovieTracker.UnitTests." + UUID().uuidString)
        defer { try? store.remove() }
        try store.save("nonsecret-fixture")
        for invalid in ["", "   ", "bad\r\nAuthorization: header", "YOUR_TMDB_API_READ_ACCESS_TOKEN"] {
            XCTAssertThrowsError(try store.save(invalid))
            XCTAssertEqual(try store.read(), "nonsecret-fixture")
        }
    }
}

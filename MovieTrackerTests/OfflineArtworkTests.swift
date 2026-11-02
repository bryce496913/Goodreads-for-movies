import UIKit
import XCTest
@testable import MovieTracker

final class OfflineArtworkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_767_225_600)
    private var png: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")! }
    private func url(_ name: String) -> URL { URL(string: "https://image.tmdb.org/t/p/w185/\(name).png")! }

    @MainActor func testMemoryCacheLRUCapacityExpiryAndRelaunchFallback() {
        let cache = ProviderArtworkCache(capacity: 2)
        XCTAssertTrue(cache.save(png, url: url("a"), at: now))
        XCTAssertTrue(cache.save(png, url: url("b"), at: now))
        XCTAssertNotNil(cache.image(url("a"), at: now)) // Read promotes a; b is evicted.
        XCTAssertTrue(cache.save(png, url: url("c"), at: now))
        XCTAssertNil(cache.image(url("b"), at: now))
        XCTAssertNotNil(cache.image(url("a"), at: now))
        cache.expire(at: now.addingTimeInterval(MetadataPolicy.retention))
        XCTAssertEqual(cache.byteCount, 0); XCTAssertNil(cache.image(url("a"), at: now))
        XCTAssertNil(ProviderArtworkCache().image(url("c"), at: now)) // A new process/cache has no promised disk copy.
    }

    @MainActor func testMemoryByteBudgetAndUnsafeOrOversizedArtworkRejection() {
        let cost = png.count + 4, cache = ProviderArtworkCache(maximumBytes: (png.count + 4) * 2 - 1)
        XCTAssertTrue(cache.save(png, url: url("a"), at: now))
        XCTAssertTrue(cache.save(png, url: url("b"), at: now))
        XCTAssertEqual(cache.byteCount, cost); XCTAssertNil(cache.image(url("a"), at: now))
        XCTAssertFalse(cache.save(Data(repeating: 0, count: 2_000_001), url: url("huge"), at: now))
        XCTAssertFalse(cache.save(Data("invalid image".utf8), url: url("invalid"), at: now))
        for raw in ["https://image.tmdb.org/t/p/original/a.jpg", "https://other.example/t/p/w185/a.png", "https://image.tmdb.org/t/p/w185/a.png?token=fixture", "http://image.tmdb.org/t/p/w185/a.png"] {
            XCTAssertFalse(cache.save(png, url: URL(string: raw)!, at: now))
        }
        cache.clear(); XCTAssertEqual(cache.byteCount, 0)
    }

    @MainActor func testTwoConsumersShareRequestAndCancelingOneKeepsOtherAlive() async throws {
        let cache = ProviderArtworkCache(), transport = OfflineArtworkTransport(), joined = ArtworkSignal()
        let date = now
        let loader = ProviderArtworkLoader(cache: cache, transport: transport, clock: { date }, didRegister: { count in
            if count == 2 { Task { await joined.signal() } }
        })
        let location = url("shared")
        let first = Task { _ = try await loader.image(location) }
        await transport.waitForRequest()
        let second = Task { _ = try await loader.image(location) }
        await joined.wait()
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected per-consumer cancellation before response") }
        catch { XCTAssertTrue(error is CancellationError) }
        await transport.complete(.success(MetadataHTTPResponse(data: png, status: 200, retryAfter: nil)))
        _ = try await second.value
        let calls = await transport.calls; XCTAssertEqual(calls, 1)
        XCTAssertNotNil(cache.image(location, at: now))
    }

    @MainActor func testCanceledLastConsumerCannotPopulateCacheFromLateResponse() async throws {
        let cache = ProviderArtworkCache(), transport = OfflineArtworkTransport(), date = now
        let loader = ProviderArtworkLoader(cache: cache, transport: transport, clock: { date })
        let location = url("canceled")
        let pending = Task { _ = try await loader.image(location) }
        await transport.waitForRequest(); pending.cancel()
        do { _ = try await pending.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        await transport.complete(.success(MetadataHTTPResponse(data: png, status: 200, retryAfter: nil)))
        // A noncooperative transport completion is ignored after the flight lost its last waiter.
        XCTAssertNil(cache.image(location, at: now)); XCTAssertEqual(cache.byteCount, 0)
    }

    @MainActor func testClearDuringFlightPreventsCacheRepopulationAndPublication() async throws {
        let cache = ProviderArtworkCache(), transport = OfflineArtworkTransport(), date = now
        let loader = ProviderArtworkLoader(cache: cache, transport: transport, clock: { date })
        let location = url("clear")
        let pending = Task { _ = try await loader.image(location) }
        await transport.waitForRequest(); cache.clear()
        await transport.complete(.success(MetadataHTTPResponse(data: png, status: 200, retryAfter: nil)))
        do { _ = try await pending.value; XCTFail("Expected invalidated flight") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(cache.image(location, at: now))
    }

    @MainActor func testOfflineImageFailureTerminatesAndExplicitRetryRecovers() async throws {
        let cache = ProviderArtworkCache(), transport = OfflineArtworkTransport(), date = now
        let loader = ProviderArtworkLoader(cache: cache, transport: transport, clock: { date })
        let location = url("retry")
        let failed = Task { _ = try await loader.image(location) }
        await transport.waitForRequest(); await transport.complete(.failure(MetadataError.offline))
        do { _ = try await failed.value; XCTFail("Expected offline failure") } catch { XCTAssertEqual(error as? MetadataError, .offline) }
        XCTAssertNil(cache.image(location, at: now))
        let retry = Task { _ = try await loader.image(location) }
        await transport.waitForRequest(count: 2)
        await transport.complete(.success(MetadataHTTPResponse(data: png, status: 200, retryAfter: nil)))
        _ = try await retry.value
        XCTAssertNotNil(cache.image(location, at: now))
        _ = try await loader.image(location)
        let calls = await transport.calls; XCTAssertEqual(calls, 2)
    }

    @MainActor func testInvalidArtworkURLDoesNotStartRequest() async {
        let transport = OfflineArtworkTransport(), loader = ProviderArtworkLoader(cache: ProviderArtworkCache(), transport: transport)
        do { _ = try await loader.image(URL(string: "https://image.tmdb.org/t/p/original/a.jpg")!); XCTFail("Expected sized-URL validation") }
        catch { XCTAssertEqual(error as? MetadataError, .invalidIdentifier) }
        let calls = await transport.calls; XCTAssertEqual(calls, 0)
    }
}

/// Deliberately noncooperative transport verifies late-response protection without real connectivity.
private actor OfflineArtworkTransport: MetadataTransport {
    private var response: CheckedContinuation<MetadataHTTPResponse, Error>?
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        calls += 1
        return try await withCheckedThrowingContinuation {
            response = $0; arrivals.removeValue(forKey: calls)?.resume()
        }
    }
    func waitForRequest(count: Int = 1) async {
        if calls >= count { return }
        await withCheckedContinuation { arrivals[count] = $0 }
    }
    func complete(_ result: Result<MetadataHTTPResponse, Error>) { response?.resume(with: result); response = nil }
}
private actor ArtworkSignal {
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { signaled = true; continuation?.resume(); continuation = nil }
    func wait() async { if signaled { return }; await withCheckedContinuation { continuation = $0 } }
}

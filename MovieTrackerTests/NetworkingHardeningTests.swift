import SwiftData
import XCTest
@testable import MovieTracker

final class NetworkingHardeningTests: XCTestCase {
    private let movieID = MediaID(kind: .movie, value: "tmdb:1")
    private let page = #"{"page":1,"total_pages":1,"total_results":1,"results":[{"id":1,"title":"Movie","release_date":null,"poster_path":null}]}"#

    @MainActor func testConfigurationFailuresAndRedactionAreDistinct() throws {
        for raw in ["", "  ", "YOUR_TMDB_API_READ_ACCESS_TOKEN", "ACCESS_TOKEN"] {
            XCTAssertThrowsError(try TMDBConfiguration(readAccessToken: raw)) { XCTAssertEqual($0 as? MetadataError, .missingCredential) }
        }
        for raw in ["Bearer nonsecret-fixture", "bad\nheader", "token with spaces"] {
            XCTAssertThrowsError(try TMDBConfiguration(readAccessToken: raw)) { XCTAssertEqual($0 as? MetadataError, .invalidCredentialFormat) }
        }
        let marker = "nonsecret-redaction-fixture"
        let config = try TMDBConfiguration.localDevelopment(environment: ["TMDB_READ_ACCESS_TOKEN": "  " + marker + "  "])
        XCTAssertEqual(config.readAccessToken, marker)
        XCTAssertFalse(String(describing: config).contains(marker)); XCTAssertFalse(String(reflecting: config).contains(marker))
        XCTAssertFalse(String(describing: Mirror(reflecting: config).children.map { String(describing: $0.value) }).contains(marker))
    }
    @MainActor func testAllMajorHTTPFailuresHaveTypedSanitizedErrorsWithoutRetry() async throws {
        let cases: [(Int, MetadataError)] = [(401, .unauthorized), (403, .forbidden), (404, .notFound),
            (429, .rateLimited(retryAfter: "60")), (500, .server(status: 500)), (502, .server(status: 502)),
            (503, .server(status: 503)), (504, .server(status: 504)), (302, .http(status: 302))]
        for (status, expected) in cases {
            let stub = HTTPFixtureTransport([.success(response("nonsecret-backend-response-must-not-display", status: status, retryAfter: status == 429 ? "60" : nil))])
            let service = try makeService(stub, policy: .none)
            await assertError(expected) { _ = try await service.searchMovies(query: "fixture", page: 1) }
            let requests = await stub.requests; XCTAssertEqual(requests.count, 1)
            XCTAssertFalse(expected.localizedDescription.contains("nonsecret-backend-response"))
        }
    }
    @MainActor func testTransientFailureRecoversWithBoundedBackoffAndIdenticalGET() async throws {
        let time = NetworkTestClock()
        let stub = HTTPFixtureTransport([.success(response("ignored", status: 503)), .success(response("ignored", status: 502)), .success(response(page))])
        let result = try await makeService(stub, time: time).searchMovies(query: "a & b", page: 1)
        XCTAssertEqual(result.items.first?.title, "Movie"); XCTAssertNil(result.items.first?.posterReference)
        XCTAssertEqual(time.delays, [0.5, 1])
        XCTAssertEqual(result.items.first?.metadataRetrievedAt, time.now)
        let requests = await stub.requests
        XCTAssertEqual(requests.count, 3); XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(Set(requests.compactMap(\.url)).count, 1)
        XCTAssertFalse(requests.first?.url?.absoluteString.contains("nonsecret-network-fixture") ?? true)
    }
    @MainActor func testRetryLimitStopsAfterThreeAttempts() async throws {
        let time = NetworkTestClock()
        let stub = HTTPFixtureTransport(Array(repeating: .success(response("ignored", status: 500)), count: 4))
        await assertError(.server(status: 500)) { _ = try await self.makeService(stub, time: time).searchMovies(query: "fixture", page: 1) }
        let requests = await stub.requests
        XCTAssertEqual(requests.count, 3); XCTAssertEqual(time.delays, [0.5, 1])
    }
    @MainActor func testLongRetryAfterBlocksNewQueriesWithoutSleepingOrSendingEarly() async throws {
        let time = NetworkTestClock()
        let stub = HTTPFixtureTransport([.success(response("ignored", status: 429, retryAfter: "60")), .success(response(page))])
        let service = try makeService(stub, time: time)
        await assertError(.rateLimited(retryAfter: "60")) { _ = try await service.searchMovies(query: "first", page: 1) }
        await assertError(.rateLimited(retryAfter: "60")) { _ = try await service.searchMovies(query: "new query", page: 1) }
        let before = await stub.requests.count; XCTAssertEqual(before, 1); XCTAssertTrue(time.delays.isEmpty)
        time.advance(60)
        let result = try await service.searchMovies(query: "new query", page: 1)
        XCTAssertEqual(result.items.count, 1)
        let after = await stub.requests.count; XCTAssertEqual(after, 2)
    }
    @MainActor func testShortRetryAfterIsRespectedAndTotalWaitBudgetStopsTheLoop() async throws {
        let time = NetworkTestClock()
        let stub = HTTPFixtureTransport(Array(repeating: .success(response("ignored", status: 429, retryAfter: "2")), count: 4))
        await assertError(.rateLimited(retryAfter: "2")) { _ = try await self.makeService(stub, time: time).searchMovies(query: "fixture", page: 1) }
        let count = await stub.requests.count
        XCTAssertEqual(count, 2); XCTAssertEqual(time.delays, [2])
    }
    @MainActor func testHTTPDateRetryAfterAndMalformedHeadersNeverExposeRawValues() async throws {
        let time = NetworkTestClock() // 2026-01-01 00:00 UTC.
        let stub = HTTPFixtureTransport([.success(response("ignored", status: 503, retryAfter: "Thu, 01 Jan 2026 00:01:00 GMT")), .success(response(page))])
        let service = try makeService(stub, time: time)
        await assertError(.server(status: 503)) { _ = try await service.searchMovies(query: "fixture", page: 1) }
        await assertError(.server(status: 503)) { _ = try await service.searchTVShows(query: "fixture", page: 1) }
        let count = await stub.requests.count; XCTAssertEqual(count, 1)
        XCTAssertNil(MetadataRetryPolicy.retryAfterSeconds("Bearer nonsecret-header-fixture", at: time.now))
        XCTAssertNil(MetadataRetryPolicy.retryAfterSeconds("-1", at: time.now))
        XCTAssertNil(MetadataRetryPolicy.retryAfterSeconds("nan", at: time.now))
        XCTAssertNil(MetadataRetryPolicy.retryAfterSeconds("inf", at: time.now))
        let malicious = HTTPFixtureTransport([.success(response("ignored", status: 429, retryAfter: "Bearer nonsecret-header-fixture"))])
        await assertError(.rateLimited(retryAfter: nil)) { _ = try await self.makeService(malicious, policy: .none).searchMovies(query: "fixture", page: 1) }
    }
    @MainActor func testTransientConnectivityCategoriesRecoverWhileOfflineAndTLSDoNotRetry() async throws {
        for (code, expected) in [(URLError.timedOut, MetadataError.timedOut), (.networkConnectionLost, .connectionLost),
                                 (.cannotConnectToHost, .connectionFailed), (.cannotFindHost, .dnsFailure), (.dnsLookupFailed, .dnsFailure)] {
            let failing = HTTPFixtureTransport([.failure(URLError(code))])
            await assertError(expected) { _ = try await self.makeService(failing, policy: .none).searchMovies(query: "fixture", page: 1) }
            let recovering = HTTPFixtureTransport([.failure(URLError(code)), .success(response(page))])
            let value = try await makeService(recovering).searchMovies(query: "fixture", page: 1)
            XCTAssertEqual(value.items.count, 1)
            let count = await recovering.requests.count; XCTAssertEqual(count, 2)
        }
        for (code, expected) in [(URLError.notConnectedToInternet, MetadataError.offline), (.dataNotAllowed, .offline),
                                 (.serverCertificateUntrusted, .secureTransport), (.secureConnectionFailed, .secureTransport)] {
            let stub = HTTPFixtureTransport([.failure(URLError(code)), .success(response(page))])
            await assertError(expected) { _ = try await self.makeService(stub).searchMovies(query: "fixture", page: 1) }
            let count = await stub.requests.count; XCTAssertEqual(count, 1)
        }
    }
    @MainActor func testAuthForbiddenNotFoundAndUnimplementedServiceAreNeverAutoRetried() async throws {
        for (status, expected) in [(401, MetadataError.unauthorized), (403, .forbidden), (404, .notFound), (501, .server(status: 501))] {
            let stub = HTTPFixtureTransport([.success(response("ignored", status: status)), .success(response(page))])
            let time = NetworkTestClock()
            await assertError(expected) { _ = try await self.makeService(stub, time: time).searchMovies(query: "fixture", page: 1) }
            let count = await stub.requests.count; XCTAssertEqual(count, 1); XCTAssertTrue(time.delays.isEmpty)
        }
    }
    @MainActor func testCancellationInterruptsBackoffBeforeTheNextRequest() async throws {
        let stub = HTTPFixtureTransport([.success(response("ignored", status: 503)), .success(response(page))])
        let gate = RetryEntryGate()
        let service = TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: "nonsecret-network-fixture"), transport: stub,
            wait: { _ in await gate.enter(); try await Task.sleep(for: .seconds(60)) })
        let task = Task { try await service.searchMovies(query: "fixture", page: 1) }
        await gate.waitForEntry(); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await stub.requests.count; XCTAssertEqual(count, 1)
    }
    @MainActor func testAuthorizationIsRecheckedAfterBackoff() async throws {
        let stub = HTTPFixtureTransport([.success(response("ignored", status: 503)), .success(response(page))])
        let gate = NetworkAuthorizationGate(), time = NetworkTestClock()
        let service = TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: "nonsecret-network-fixture"), transport: stub,
            clock: { time.now }, authorization: { try await gate.check() }, wait: { delay in time.recordWait(delay); await gate.revoke() })
        await assertError(.unauthorized) { _ = try await service.searchMovies(query: "fixture", page: 1) }
        let count = await stub.requests.count; XCTAssertEqual(count, 1)
    }
    @MainActor func testCanceledLateRateLimitStillProtectsTheSharedClient() async throws {
        let stub = LateHTTPFixtureTransport(), time = NetworkTestClock()
        let service = try makeService(stub, time: time)
        let obsolete = Task { try await service.searchMovies(query: "old", page: 1) }
        await stub.waitForRequest(); obsolete.cancel()
        await stub.complete(response("ignored", status: 429, retryAfter: "60"))
        do { _ = try await obsolete.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        await assertError(.rateLimited(retryAfter: "60")) { _ = try await service.searchMovies(query: "new", page: 1) }
        let count = await stub.calls; XCTAssertEqual(count, 1)
    }
    @MainActor func testInvalidJSONEmptyBodyAndWrongPageAreNotRetried() async throws {
        for (payload, expected) in [("not JSON", MetadataError.invalidPayload), ("", .emptyResponse),
            (#"{"page":2,"total_pages":2,"total_results":0,"results":[]}"#, .invalidPayload)] {
            let stub = HTTPFixtureTransport([.success(response(payload)), .success(response(page))])
            await assertError(expected) { _ = try await self.makeService(stub).searchMovies(query: "fixture", page: 1) }
            let count = await stub.requests.count; XCTAssertEqual(count, 1)
        }
    }
    @MainActor func testMissingFieldsRemainUnknownAndMediaTypesStayDistinct() async throws {
        let stub = HTTPFixtureTransport([
            .success(response(#"{"id":1,"title":"Movie","release_date":null,"poster_path":null,"runtime":null}"#)),
            .success(response(#"{"id":1,"name":"TV","first_air_date":"bad-date","number_of_episodes":null,"number_of_seasons":null}"#)),
            .success(response(#"{"season_number":1,"episodes":[{"id":9,"episode_number":1,"air_date":null,"name":null}]}"#))])
        let service = try makeService(stub)
        let movie = try await service.movieDetails(id: movieID), show = try await service.tvShowDetails(id: MediaID(kind: .tvShow, value: "tmdb:1"))
        XCTAssertNotEqual(movie.id, show.id); XCTAssertNil(movie.posterReference); XCTAssertNil(movie.releaseDate)
        XCTAssertNil(show.episodeCount); XCTAssertNil(show.seasonCount); XCTAssertNil(show.firstAirDate)
        let season = try await service.tvSeasonDetails(for: show.id, number: 1)
        XCTAssertNil(season.episodes.first?.airDate); XCTAssertEqual(season.episodes.first?.title, "Episode 1")
    }
    @MainActor func testMalformedRefreshDoesNotCorruptPersonalDataAndLaterSuccessRecovers() async throws {
        let time = NetworkTestClock(), oldDate = NetworkTestClock.start.addingTimeInterval(-40 * 86_400)
        let old = MediaSearchResult.movie(Movie(id: movieID.value, title: "Prior title", metadataRetrievedAt: oldDate))
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true), clock: { time.now })
        try store.setPersonalRating(PersonalRating(halfStarUnits: 9), media: old)
        try store.saveReview(id: UUID(), media: old, text: "Private user text", now: time.now)
        try store.metadataRefreshSucceeded(old)
        let originalID = store.entries.first?.id
        let stub = HTTPFixtureTransport([.success(response("bad JSON")), .success(response(#"{"id":1,"title":"Fresh title"}"#))])
        let model = MediaDetailModel(destination: SearchItem(old).destination, service: try makeService(stub, time: time),
            cache: MediaDetailCache(clock: { time.now }), clock: { time.now })
        await model.load(store: store, force: true)
        XCTAssertEqual(model.error, .invalidPayload); XCTAssertEqual(store.entries.first?.savedTitle, "Prior title")
        XCTAssertEqual(store.metadataState(for: movieID)?.lastSuccessfulFetch, oldDate)
        await model.load(store: store, force: true)
        XCTAssertNil(model.error); XCTAssertEqual(store.entries.first?.savedTitle, "Fresh title")
        XCTAssertEqual(store.entries.first?.id, originalID); XCTAssertEqual(store.entries.first?.ratingHalfStarUnits, 9)
        XCTAssertEqual(store.personalReviews.first?.text, "Private user text")
    }
    @MainActor private func response(_ body: String, status: Int = 200, retryAfter: String? = nil) -> MetadataHTTPResponse {
        MetadataHTTPResponse(data: Data(body.utf8), status: status, retryAfter: retryAfter)
    }
    @MainActor private func makeService(_ transport: any MetadataTransport, policy: MetadataRetryPolicy = .standard, time: NetworkTestClock = NetworkTestClock()) throws -> TMDBMetadataService {
        TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: "nonsecret-network-fixture"), transport: transport,
            clock: { time.now }, retryPolicy: policy, wait: { delay in time.recordWait(delay) })
    }
    @MainActor private func assertError(_ expected: MetadataError, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected typed failure") } catch { XCTAssertEqual(error as? MetadataError, expected) }
    }
}

private actor HTTPFixtureTransport: MetadataTransport {
    private var responses: [Result<MetadataHTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Result<MetadataHTTPResponse, Error>]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw MetadataError.transport }
        return try responses.removeFirst().get()
    }
}
private final class NetworkTestClock: @unchecked Sendable {
    static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private let lock = NSLock(); private var value = NetworkTestClock.start; private var waits: [TimeInterval] = []
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    var delays: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return waits }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
    func recordWait(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; waits.append(seconds); value.addTimeInterval(seconds) }
}
private actor RetryEntryGate {
    private var entered = false; private var waiter: CheckedContinuation<Void, Never>?
    func enter() { entered = true; waiter?.resume(); waiter = nil }
    func waitForEntry() async { if !entered { await withCheckedContinuation { waiter = $0 } } }
}
private actor NetworkAuthorizationGate {
    private var authorized = true
    func revoke() { authorized = false }
    func check() throws { if !authorized { throw MetadataError.unauthorized } }
}
private actor LateHTTPFixtureTransport: MetadataTransport {
    private var pending: CheckedContinuation<MetadataHTTPResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        calls += 1
        return await withCheckedContinuation { pending = $0; waiter?.resume(); waiter = nil }
    }
    func waitForRequest() async { if pending == nil { await withCheckedContinuation { waiter = $0 } } }
    func complete(_ response: MetadataHTTPResponse) { pending?.resume(returning: response); pending = nil }
}

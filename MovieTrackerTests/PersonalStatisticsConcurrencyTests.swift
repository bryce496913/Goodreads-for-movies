import XCTest
@testable import MovieTracker

@MainActor
final class PersonalStatisticsConcurrencyTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
    private func source(_ year: Int = 2026, revision: Int = 1, now: Date? = nil) -> PersonalStatisticsModel.Source {
        .init(revision: revision, invalidation: 0, year: year, timeZone: .gmt, referenceDate: now ?? self.now)
    }
    func testReplacingYearDiscardsNoncooperativeStaleResult() async throws {
        let gate = StatisticsGate()
        let model = PersonalStatisticsModel(now: now, timeZone: .gmt, aggregate: { try await gate.aggregate($0, $1, $2, $3) })
        let old = Task { await model.refresh(.init(), source: source(2024)) }
        await gate.waitForCalls(1)
        let new = Task { await model.refresh(.init(), source: source(2025)) }
        await gate.waitForCalls(2)
        try await gate.finish(1); await new.value
        try await gate.finish(0); await old.value
        XCTAssertEqual(model.snapshot?.year, 2025)
        XCTAssertTrue(model.isReady(for: source(2025)))
        XCTAssertFalse(model.isLoading)
    }
    func testCancelAndReplacementCanRecoverWithoutPublishingCanceledResult() async throws {
        let gate = StatisticsGate()
        let model = PersonalStatisticsModel(now: now, aggregate: { try await gate.aggregate($0, $1, $2, $3) })
        let task = Task { await model.refresh(.init(), source: source()) }
        await gate.waitForCalls(1)
        task.cancel(); try await gate.finish(0); await task.value
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.isLoading)
        let retry = Task { await model.refresh(.init(), source: source()) }
        await gate.waitForCalls(2); try await gate.finish(1); await retry.value
        XCTAssertTrue(model.isReady(for: source()))
    }
    func testMinuteRendersDoNotReaggregateButRevisionAndDayInvalidate() async throws {
        let gate = StatisticsGate()
        let model = PersonalStatisticsModel(now: now, aggregate: { try await gate.aggregate($0, $1, $2, $3) })
        let first = Task { await model.refresh(.init(), source: source()) }
        await gate.waitForCalls(1); try await gate.finish(0); await first.value
        await model.refresh(.init(), source: source(now: now.addingTimeInterval(60)))
        let count = await gate.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(model.isReady(for: source(now: now.addingTimeInterval(-60))))
        XCTAssertFalse(model.isReady(for: source(revision: 2)))
        XCTAssertFalse(model.isReady(for: source(now: now.addingTimeInterval(86_400))))
        let changedZone = PersonalStatisticsModel.Source(revision: 1, invalidation: 0, year: 2026,
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 3600)), referenceDate: now)
        XCTAssertFalse(model.isReady(for: changedZone))
    }
    func testJustCommittedEpisodeMarkUsesFreshEvaluationWithoutChangingObservationKey() async {
        let id = EpisodeID(seriesID: .init(kind: .tvShow, value: "fixture:1"), providerValue: "fixture:episode")
        let input = PersonalStatisticsInput(episodes: [.init(id: id, watched: true, markedAt: now.addingTimeInterval(30))])
        let model = PersonalStatisticsModel(now: now)
        await model.refresh(input, source: source(), now: now.addingTimeInterval(31))
        XCTAssertEqual(model.snapshot?.episodeMarks, 1)
        XCTAssertTrue(model.isReady(for: source()))
    }

    func testGenreLeaseInvalidatesCachedProjectionAtExactExpiry() async throws {
        let id = MediaID(kind: .movie, value: "tmdb:1")
        let receipt = now.addingTimeInterval(-MetadataPolicy.retention + 60)
        let media = MediaSearchResult.movie(Movie(id: id.value, title: "Cached", genres: [.init(id: "tmdb:18", name: "Drama")], metadataRetrievedAt: receipt))
        let input = PersonalStatisticsInput(titles: [
            .init(recordID: LargeLibraryFixtures.uuid(1), mediaID: id, updatedAt: now, ratingUnits: nil, legacyRating: nil, mediaData: try JSONEncoder().encode(media))
        ], viewings: [.init(id: LargeLibraryFixtures.uuid(2), mediaID: id,
                          watchedDate: Date(timeIntervalSince1970: 1_767_225_600), mediaData: nil)])
        let model = PersonalStatisticsModel(now: now)
        await model.refresh(input, source: source())
        XCTAssertEqual(model.snapshot?.genres.count, 1)
        XCTAssertTrue(model.isReady(for: source(now: now.addingTimeInterval(59))))
        XCTAssertFalse(model.isReady(for: source(now: now.addingTimeInterval(60))))
        await model.refresh(input, source: source(now: now.addingTimeInterval(60)))
        XCTAssertTrue(model.snapshot?.genres.isEmpty == true)
        XCTAssertEqual(model.snapshot?.movieEvents, 1)
    }
}

/// Ignores cancellation deliberately; the presentation model must guard publication too.
private actor StatisticsGate {
    private struct Call {
        let input: PersonalStatisticsInput
        let year: Int
        let now: Date
        let zone: TimeZone
        let continuation: CheckedContinuation<PersonalStatisticsSnapshot, Error>
    }
    private var calls: [Call] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    var count: Int { calls.count }
    func aggregate(_ input: PersonalStatisticsInput, _ year: Int, _ now: Date, _ zone: TimeZone) async throws -> PersonalStatisticsSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(input: input, year: year, now: now, zone: zone, continuation: continuation))
            let ready = observers.filter { calls.count >= $0.0 }
            observers.removeAll { calls.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func finish(_ index: Int) throws {
        let call = calls[index]
        call.continuation.resume(returning: try DashboardAggregator.personalStatistics(call.input, year: call.year, now: call.now, timeZone: call.zone))
    }
}

import SwiftData
import XCTest
@testable import MovieTracker

final class ViewingCalendarTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private func calendar(_ zone: String = "UTC", first: Int = 1) -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; value.locale = locale; value.firstWeekday = first
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func stamp(_ id: Int, watched: Date?, recorded: Date) -> ViewingCalendarStamp {
        .init(id: LargeLibraryFixtures.uuid(id), watchedDate: watched, recordedAt: recorded)
    }
    func testLeapMonthAndSundayMondayWeekStartsAndLocalizedHeadings() {
        let sunday = ViewingCalendarProjection.month(containing: date(2024, 2, 15), calendar: calendar(), locale: locale)
        XCTAssertEqual(sunday.days.count, 29); XCTAssertEqual(sunday.slots.count, 35)
        XCTAssertEqual(sunday.slots.prefix(4).compactMap { $0 }.count, 0)
        XCTAssertEqual(sunday.slots[4], date(2024, 2, 1)); XCTAssertEqual(sunday.weekdays.first, "Sun")
        let monday = ViewingCalendarProjection.month(containing: date(2024, 2, 15), calendar: calendar(first: 2), locale: locale)
        XCTAssertEqual(monday.slots[3], date(2024, 2, 1)); XCTAssertEqual(monday.weekdays.first, "Mon")
        let normal = ViewingCalendarProjection.month(containing: date(2023, 2, 1), calendar: calendar(), locale: locale)
        XCTAssertEqual(normal.days.count, 28)
        let french = ViewingCalendarProjection.month(containing: date(2024, 2, 1), calendar: calendar(first: 2), locale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(french.title.lowercased().contains("février"))
    }
    func testVariableMonthLengthsAndNonGregorianCalendar() {
        for month in 1...12 {
            let value = ViewingCalendarProjection.month(containing: date(2024, month, 15), calendar: calendar(), locale: locale)
            XCTAssertTrue(value.slots.count.isMultiple(of: 7)); XCTAssertEqual(Set(value.days).count, value.days.count)
            XCTAssertEqual(value.days.count, calendar().range(of: .day, in: .month, for: date(2024, month, 1))?.count)
        }
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = .gmt; buddhist.firstWeekday = 2
        let value = ViewingCalendarProjection.month(containing: date(2024, 2, 5), calendar: buddhist, locale: Locale(identifier: "th_TH"))
        XCTAssertEqual(value.days.count, 29); XCTAssertEqual(buddhist.component(.year, from: value.start), 2567)
    }
    func testGroupingKeepsIndependentSameDayEventsAndStableRecordedTimeTies() throws {
        let day = date(2024, 2, 29), recorded = date(2025, 1, 1)
        let stamps = [stamp(2, watched: day, recorded: recorded), stamp(1, watched: day, recorded: recorded), stamp(3, watched: day, recorded: recorded.addingTimeInterval(1))]
        let value = try ViewingCalendarProjection.index(stamps, calendar: calendar())
        XCTAssertEqual(value.days[day], [3, 1, 2].map(LargeLibraryFixtures.uuid))
        XCTAssertEqual(try ViewingCalendarProjection.index(Array(stamps.reversed()), calendar: calendar()).days[day], value.days[day])
    }
    func testUndatedNeverUsesRecordedDayAndInvalidDateDoesNotInventOne() throws {
        let now = date(2026, 1, 1)
        let value = try ViewingCalendarProjection.index([stamp(1, watched: nil, recorded: now), stamp(2, watched: Date(timeIntervalSinceReferenceDate: .nan), recorded: now)], calendar: calendar())
        XCTAssertTrue(value.days.isEmpty); XCTAssertEqual(value.undated, [LargeLibraryFixtures.uuid(1)])
    }
    func testStoredCivilDaysDoNotShiftAcrossExtremeTimeZonesOrYearBoundary() throws {
        for zone in ["Pacific/Kiritimati", "America/Los_Angeles", "Etc/GMT+12"] {
            let cal = calendar(zone)
            for watched in [date(2023, 12, 31), date(2024, 1, 1), date(2024, 2, 29), date(2024, 12, 31, hour: 23)] {
                let actual = try XCTUnwrap(ViewingCalendarProjection.day(for: watched, calendar: cal))
                XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: actual), calendar().dateComponents([.year, .month, .day], from: watched))
            }
        }
    }
    func testDSTTransitionsKeepCivilGroupingAndMonthConstruction() throws {
        let cal = calendar("America/New_York")
        let march = ViewingCalendarProjection.month(containing: date(2024, 3, 15), calendar: cal, locale: locale)
        XCTAssertEqual(march.days.count, 31)
        let ten = try XCTUnwrap(ViewingCalendarProjection.day(for: date(2024, 3, 10), calendar: cal))
        let eleven = try XCTUnwrap(ViewingCalendarProjection.day(for: date(2024, 3, 11), calendar: cal))
        XCTAssertEqual(eleven.timeIntervalSince(ten), 23 * 3_600)
        let november = ViewingCalendarProjection.month(containing: date(2024, 11, 15), calendar: cal, locale: locale)
        XCTAssertEqual(november.days.count, 30)
        let three = try XCTUnwrap(ViewingCalendarProjection.day(for: date(2024, 11, 3), calendar: cal))
        let four = try XCTUnwrap(ViewingCalendarProjection.day(for: date(2024, 11, 4), calendar: cal))
        XCTAssertEqual(four.timeIntervalSince(three), 25 * 3_600)
    }
    func testSkippedLocalCivilDateIsNotSilentlyMovedAndMonthDoesNotLeakIntoJanuary() throws {
        let cal = calendar("Pacific/Apia"), skipped = date(2011, 12, 30)
        XCTAssertNil(ViewingCalendarProjection.day(for: skipped, calendar: cal))
        let value = try ViewingCalendarProjection.index([stamp(1, watched: skipped, recorded: date(2012, 1, 1))], calendar: cal)
        XCTAssertTrue(value.days.isEmpty); XCTAssertEqual(value.unavailableDates, 1); XCTAssertTrue(value.undated.isEmpty)
        let month = ViewingCalendarProjection.month(containing: date(2011, 12, 15), calendar: cal, locale: locale)
        XCTAssertTrue(month.days.allSatisfy { cal.component(.month, from: $0) == 12 })
        for (index, value) in month.slots.enumerated() {
            if let day = value { XCTAssertEqual(index % 7, (cal.component(.weekday, from: day) - cal.firstWeekday + 7) % 7) }
        }
    }
    @MainActor func testMonthNavigationYearBoundaryAndSelectionStateWithoutReprojection() {
        let model = ViewingCalendarModel(now: date(2024, 12, 31), calendar: calendar(), locale: locale)
        model.moveMonth(1); XCTAssertEqual(model.month.start, date(2025, 1, 1))
        model.select(date(2025, 1, 22)); let selected = model.selectedDay
        XCTAssertEqual(model.selectedDay, selected); XCTAssertEqual(model.month.start, date(2025, 1, 1))
        model.moveMonth(-1); XCTAssertEqual(model.month.start, date(2024, 12, 1))
        model.today(date(2024, 2, 29)); XCTAssertEqual(model.selectedDay, date(2024, 2, 29))
    }
    @MainActor func testDateEditingDeletionAndReviewRatingPreservationUseExistingStore() async throws {
        let store = try BackupFixtures.store(), media = MediaSearchResult.movie(Movie(id: "fixture:calendar", title: "Offline saved movie"))
        let a = LargeLibraryFixtures.uuid(1), b = LargeLibraryFixtures.uuid(2), original = date(2024, 2, 29), moved = date(2024, 3, 1)
        try store.saveViewingEvent(id: a, media: media, watchedDate: original)
        try store.saveViewingEvent(id: b, media: media, watchedDate: original)
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: media)
        try store.saveReview(id: UUID(), media: media, text: "Keep review", eventID: a)
        let model = ViewingCalendarModel(now: original, calendar: calendar(), locale: locale)
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar(), locale: locale))
        XCTAssertEqual(model.selectedEvents.count, 2)
        try store.saveViewingEvent(id: a, media: media, watchedDate: moved)
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar(), locale: locale))
        XCTAssertEqual(model.selectedEvents.map(\.id), [b]); model.moveMonth(1); XCTAssertEqual(model.selectedEvents.map(\.id), [a])
        try store.deleteViewingEvent(a)
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar(), locale: locale))
        XCTAssertTrue(model.selectedEvents.isEmpty); XCTAssertEqual(store.viewingEvents.count, 1)
        XCTAssertEqual(store.personalReviews.first?.text, "Keep review"); XCTAssertNil(store.personalReviews.first?.viewingEventID)
        XCTAssertEqual(try store.entry(for: SearchItem(media).id)?.validatedRating()?.halfStarUnits, 8)
    }
    @MainActor func testCurrentMonthIsInitialAndCachedUpdatePreservesSelectedMonthAndDayReadOnly() async throws {
        let store = try BackupFixtures.store(), model = ViewingCalendarModel(now: date(2024, 5, 10), calendar: calendar(), locale: locale)
        try store.saveViewingEvent(id: UUID(), media: .tvShow(TVShow(id: "fixture:series", title: "Series")), watchedDate: nil)
        let revision = store.revision, source = ViewingCalendarModel.Source(revision: revision, calendar: calendar(), locale: locale)
        await model.update(store.viewingEvents, source: source)
        model.moveMonth(-1); model.select(date(2024, 4, 12)); let month = model.month.start
        await model.update(store.viewingEvents, source: source)
        XCTAssertEqual(model.month.start, month); XCTAssertEqual(model.selectedDay, date(2024, 4, 12))
        XCTAssertEqual(model.undatedEvents.count, 1); XCTAssertEqual(store.revision, revision)
        try store.setFavorite(true, media: .tvShow(TVShow(id: "fixture:series", title: "Series")))
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar(), locale: locale))
        XCTAssertEqual(model.month.start, month); XCTAssertEqual(model.selectedDay, date(2024, 4, 12))
        XCTAssertEqual(model.undatedEvents.count, 1)
    }
    @MainActor func testCanceledGroupingCanRetryAndDoesNotPublishStaleIndex() async throws {
        let store = try BackupFixtures.store(), model = ViewingCalendarModel(now: date(2024, 1, 1), calendar: calendar(), locale: locale)
        let source = ViewingCalendarModel.Source(revision: store.revision, calendar: calendar(), locale: locale)
        let task = Task { await model.update(store.viewingEvents, source: source) }; task.cancel(); await task.value
        XCTAssertNil(model.revision)
        await model.update(store.viewingEvents, source: source); XCTAssertEqual(model.revision, source.revision)
    }
    @MainActor func testTimeZoneChangeAfterCanceledUpdateCannotReuseOldDayKeys() async throws {
        let store = try BackupFixtures.store(), watched = date(2024, 2, 29)
        try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(1), media: .movie(Movie(id: "fixture:zone", title: "Zone")), watchedDate: watched)
        let model = ViewingCalendarModel(now: watched, calendar: calendar(), locale: locale)
        await model.update(store.viewingEvents, source: .init(revision: store.revision, calendar: calendar(), locale: locale))
        let west = calendar("America/Los_Angeles")
        let source = ViewingCalendarModel.Source(revision: store.revision, calendar: west, locale: locale)
        let task = Task { await model.update(store.viewingEvents, source: source) }
        await Task.yield(); task.cancel(); await task.value
        await model.update(store.viewingEvents, source: source)
        XCTAssertTrue(model.isReady(for: source))
        let expected = try XCTUnwrap(ViewingCalendarProjection.day(for: watched, calendar: west))
        XCTAssertEqual(model.selectedDay, expected); XCTAssertEqual(model.index.days[expected], [LargeLibraryFixtures.uuid(1)])
        XCTAssertEqual(model.selectedEvents.count, 1)
    }
    @MainActor func testDiskReopenRebuildsOfflineCalendarAndDoesNotPersistTransientSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Calendar.store"), watched = date(2024, 2, 29)
        try autoreleasepool {
            let store = try BackupFixtures.store(at: url)
            try store.saveViewingEvent(id: LargeLibraryFixtures.uuid(1), media: .movie(Movie(id: "fixture:saved", title: "Offline")), watchedDate: watched)
        }
        let reopened = try BackupFixtures.store(at: url), model = ViewingCalendarModel(now: date(2024, 3, 15), calendar: calendar(), locale: locale)
        await model.update(reopened.viewingEvents, source: .init(revision: reopened.revision, calendar: calendar(), locale: locale))
        XCTAssertEqual(model.month.start, date(2024, 3, 1)); model.moveMonth(-1); model.select(watched)
        XCTAssertEqual(model.selectedEvents.first?.id, LargeLibraryFixtures.uuid(1))
    }
    func testFiveThousandEventsPreserveAllIDsAndUndatedCount() throws {
        let rows = (0..<5_000).map { stamp($0, watched: $0.isMultiple(of: 5) ? nil : date(2024, 1, 1).addingTimeInterval(Double($0 % 31) * 86_400), recorded: date(2025, 1, 1).addingTimeInterval(Double($0))) }
        let value = try ViewingCalendarProjection.index(rows, calendar: calendar())
        XCTAssertEqual(value.undated.count, 1_000); XCTAssertEqual(value.days.values.reduce(0) { $0 + $1.count }, 4_000)
        XCTAssertEqual(Set(value.days.values.flatMap { $0 } + value.undated).count, 5_000)
    }
}

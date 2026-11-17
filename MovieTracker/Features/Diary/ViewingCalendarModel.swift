import Foundation
import Observation

struct ViewingCalendarStamp: Sendable, Equatable {
    let id: UUID
    let watchedDate: Date?
    let recordedAt: Date
}

struct ViewingMonth: Sendable {
    let start: Date
    let title: String
    let weekdays: [String]
    let days: [Date]
    let slots: [Date?]
    let labels: [Date: String]
}

/// Read-only projection. Watched values are persisted Gregorian UTC civil dates,
/// so reconstruct their local civil day BEFORE applying the user's selected Calendar.
enum ViewingCalendarProjection {
    struct Index: Sendable {
        var days: [Date: [UUID]] = [:]
        var undated: [UUID] = []
        var unavailableDates = 0
    }
    static func day(for stored: Date, calendar: Calendar) -> Date? {
        guard stored.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let local = DiaryDates.pickerDate(from: stored, timeZone: calendar.timeZone)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        guard DiaryDates.storageDate(from: local, timeZone: calendar.timeZone) == utc.startOfDay(for: stored) else { return nil }
        return calendar.startOfDay(for: local)
    }
    static func index(_ events: [ViewingCalendarStamp], calendar: Calendar) throws -> Index {
        var groups: [Date: [ViewingCalendarStamp]] = [:], undated: [ViewingCalendarStamp] = []
        var unavailable = 0
        for event in events {
            try Task.checkCancellation()
            if let watched = event.watchedDate {
                if let date = day(for: watched, calendar: calendar) { groups[date, default: []].append(event) }
                else { unavailable += 1 }
            } else { undated.append(event) }
        }
        func ordered(_ rows: [ViewingCalendarStamp]) throws -> [UUID] {
            try rows.sorted { lhs, rhs in
                try Task.checkCancellation()
                if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt > rhs.recordedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }.map(\.id)
        }
        var result = Index(); result.unavailableDates = unavailable
        for (date, rows) in groups { result.days[date] = try ordered(rows) }
        result.undated = try ordered(undated)
        return result
    }
    static func month(containing date: Date, calendar: Calendar, locale: Locale) -> ViewingMonth {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { calendar.isDate($0, equalTo: start, toGranularity: .month) }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = locale; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        let title = formatter.string(from: start)
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? []
        let first = max(0, min(6, calendar.firstWeekday - 1))
        let weekdays = (0..<7).map { symbols.count == 7 ? symbols[($0 + first) % 7] : "" }
        let leading = (calendar.component(.weekday, from: start) - (first + 1) + 7) % 7
        var slots = Array<Date?>(repeating: nil, count: leading)
        for day in days {
            let column = (calendar.component(.weekday, from: day) - (first + 1) + 7) % 7
            while slots.count % 7 != column { slots.append(nil) }
            slots.append(day)
        }
        while !slots.count.isMultiple(of: 7) { slots.append(nil) }
        let full = DateFormatter(); full.calendar = calendar; full.locale = locale; full.timeZone = calendar.timeZone
        full.dateStyle = .full; full.timeStyle = .none
        let labels = Dictionary(uniqueKeysWithValues: days.map { ($0, full.string(from: $0)) })
        return ViewingMonth(start: start, title: title, weekdays: weekdays, days: days, slots: slots, labels: labels)
    }
    static func label(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = locale; formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

@MainActor
@Observable
final class ViewingCalendarModel {
    private(set) var calendar: Calendar
    private(set) var locale: Locale
    private(set) var month: ViewingMonth
    private(set) var selectedDay: Date
    private(set) var index = ViewingCalendarProjection.Index()
    private(set) var isUpdating = false
    private(set) var revision: Int?
    private(set) var errorMessage: String?
    @ObservationIgnored private var records: [UUID: StoredViewingEvent] = [:]
    @ObservationIgnored private var generation = UUID()
    private var prepared: Source?
    @ObservationIgnored private var lastStamps: [ViewingCalendarStamp]?
    struct Source: Hashable { let revision: Int; let calendar: Calendar; let locale: Locale }

    init(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar; self.locale = locale
        selectedDay = calendar.startOfDay(for: now)
        month = ViewingCalendarProjection.month(containing: now, calendar: calendar, locale: locale)
    }
    func isReady(for source: Source) -> Bool { prepared == source && !isUpdating }
    var selectedEvents: [StoredViewingEvent] { (index.days[selectedDay] ?? []).compactMap { records[$0] } }
    var undatedEvents: [StoredViewingEvent] { index.undated.compactMap { records[$0] } }
    func select(_ day: Date) { selectedDay = calendar.startOfDay(for: day) }
    func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month.start) else { return }
        month = ViewingCalendarProjection.month(containing: next, calendar: calendar, locale: locale)
        selectedDay = month.start
    }
    func today(_ now: Date = .now) {
        month = ViewingCalendarProjection.month(containing: now, calendar: calendar, locale: locale)
        selectedDay = calendar.startOfDay(for: now)
    }
    func update(_ events: [StoredViewingEvent], source: Source) async {
        guard prepared != source, !Task.isCancelled else { return }
        let token = UUID(); generation = token; isUpdating = true; errorMessage = nil
        defer { if generation == token { isUpdating = false } }
        let configurationChanged = calendar != source.calendar || locale != source.locale
        if configurationChanged {
            let civil = DiaryDates.storageDate(from: selectedDay, timeZone: calendar.timeZone)
            calendar = source.calendar; locale = source.locale
            selectedDay = calendar.startOfDay(for: DiaryDates.pickerDate(from: civil, timeZone: calendar.timeZone))
            month = ViewingCalendarProjection.month(containing: selectedDay, calendar: calendar, locale: locale)
        }
        let copied = events.map { ViewingCalendarStamp(id: $0.id, watchedDate: $0.watchedDate, recordedAt: $0.recordedAt) }
        // Live records stay on this actor. Only immutable stamps/Calendar cross to the worker.
        let rows = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if prepared?.calendar == source.calendar && prepared?.locale == source.locale && lastStamps == copied {
            records = rows; revision = source.revision; prepared = source
            return // Rating/metadata-only revisions do not regroup unchanged viewing dates.
        }
        let configuration = source.calendar
        let worker = Task.detached(priority: .userInitiated) { try ViewingCalendarProjection.index(copied, calendar: configuration) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == token else { return }
            records = rows; index = result; revision = source.revision; prepared = source; lastStamps = copied
        } catch is CancellationError { }
        catch { if generation == token { errorMessage = "Calendar could not be prepared. Reopen Viewing History to retry." } }
    }
}

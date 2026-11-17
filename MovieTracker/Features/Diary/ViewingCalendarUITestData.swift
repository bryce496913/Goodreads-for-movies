#if DEBUG
import Foundation

/// Explicit test flag only, inside the existing isolated UI-test container.
@MainActor enum ViewingCalendarUITestData {
    static func seed(_ store: LibraryStore) throws {
        let calendar = Calendar.current, now = Date.now
        guard let first = calendar.dateInterval(of: .month, for: now)?.start,
              let second = calendar.date(byAdding: .day, value: 1, to: first) else { return }
        let movie = MediaSearchResult.movie(Movie(id: "fixture:1", title: "Calendar movie"))
        let show = MediaSearchResult.tvShow(TVShow(id: "fixture:1", title: "Calendar series"))
        let event = UUID(uuidString: "39000000-0000-0000-0000-000000000001")!
        try store.saveViewingEvent(id: event, media: movie, watchedDate: DiaryDates.storageDate(from: first), now: now)
        try store.saveViewingEvent(id: UUID(uuidString: "39000000-0000-0000-0000-000000000002")!, media: show, watchedDate: DiaryDates.storageDate(from: first), now: now.addingTimeInterval(1))
        try store.saveViewingEvent(id: UUID(uuidString: "39000000-0000-0000-0000-000000000003")!, media: movie, watchedDate: DiaryDates.storageDate(from: second), now: now.addingTimeInterval(2))
        try store.saveViewingEvent(id: UUID(uuidString: "39000000-0000-0000-0000-000000000004")!, media: show, watchedDate: nil, now: now.addingTimeInterval(3))
        try store.setPersonalRating(PersonalRating(halfStarUnits: 8), media: movie)
        try store.saveReview(id: UUID(uuidString: "39000000-0000-0000-0000-000000000005")!, media: movie, text: "A private calendar review", eventID: event, now: now)
    }
}
#endif

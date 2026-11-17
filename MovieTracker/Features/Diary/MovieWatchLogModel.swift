import Foundation
import Observation

/// One sheet owns these stable IDs. A new sheet creates an independent repeat watch.
struct MovieWatchLog: Sendable {
    enum RatingChange: Sendable { case unchanged, set(PersonalRating?) }
    let eventID: UUID
    let reviewID: UUID
    let watchedDate: Date?
    let rating: RatingChange
    let review: String?
}

@MainActor
@Observable
final class MovieWatchLogModel {
    let media: MediaSearchResult
    let eventID = UUID()
    let reviewID = UUID()
    var dateKnown = true
    var date: Date
    var writesReview = false
    var review = ""
    private(set) var ratingEdited = false
    private var chosenRating: PersonalRating?
    private let initialRating: Result<PersonalRating?, Error>
    private let initialDay: Date
    private let timeZone: TimeZone
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var errorMessage: String?

    init(media: MediaSearchResult, rating: Result<PersonalRating?, Error> = .success(nil), now: Date = .now, timeZone: TimeZone = .current) {
        self.media = media; initialRating = rating; date = now; self.timeZone = timeZone
        initialDay = DiaryDates.storageDate(from: now, timeZone: timeZone)
    }
    var hasChanges: Bool {
        !dateKnown || DiaryDates.storageDate(from: date, timeZone: timeZone) != initialDay || ratingEdited || writesReview || !review.isEmpty
    }
    var canSave: Bool { !isSaving && !didSave && (!writesReview || !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    func currentRating() throws -> PersonalRating? {
        if ratingEdited { return chosenRating }
        return try initialRating.get()
    }
    func clearError() { errorMessage = nil }
    func chooseRating(_ value: PersonalRating?) { chosenRating = value; ratingEdited = true }

    @discardableResult func save(into store: LibraryStore, now: Date = .now) -> Bool {
        guard canSave else { return false }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            let command = MovieWatchLog(eventID: eventID, reviewID: reviewID,
                watchedDate: dateKnown ? DiaryDates.storageDate(from: date, timeZone: timeZone) : nil,
                rating: ratingEdited ? .set(chosenRating) : .unchanged, review: writesReview ? review : nil)
            try store.logMovieWatch(command, media: media, now: now, timeZone: timeZone)
            didSave = true
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}

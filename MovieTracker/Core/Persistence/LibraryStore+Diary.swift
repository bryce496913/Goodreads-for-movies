import Foundation
import SwiftData

extension LibraryStore {
    func reviews(for id: MediaID) -> [StoredPersonalReview] {
        personalReviews.filter { $0.mediaKind == id.kind.rawValue && $0.mediaValue == id.value }
    }

    func events(for id: MediaID) -> [StoredViewingEvent] {
        viewingEvents.filter { $0.mediaKind == id.kind.rawValue && $0.mediaValue == id.value }
    }

    func saveReview(id: UUID, media: MediaSearchResult, text: String, eventID: UUID? = nil,
                    legacyEntryID: UUID? = nil, now: Date = .now) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiaryError.emptyReview }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw DiaryError.invalidDate }
        let identity = SearchItem(media).id
        try writeDiary { context in
            let existing = try diaryReview(id, in: context)
            if let existing, existing.mediaID != identity { throw DiaryError.identityMismatch }
            if let eventID {
                guard let event = try diaryEvent(eventID, in: context), event.mediaID == identity else { throw DiaryError.eventUnavailable }
                let linkedEventID: UUID? = eventID
                let linked = try context.fetch(FetchDescriptor<StoredPersonalReview>(predicate: #Predicate { $0.viewingEventID == linkedEventID }))
                guard !linked.contains(where: { $0.id != id }) else { throw DiaryError.eventHasReview }
            }
            let entry = try ensureLibraryEntry(media: media)
            if let legacyEntryID {
                guard entry.id == legacyEntryID, existing != nil || entry.review != nil else { throw DiaryError.legacyChanged }
            }
            if let existing {
                if existing.text != text || existing.viewingEventID != eventID {
                    existing.text = text; existing.viewingEventID = eventID
                    existing.editedAt = max(now, existing.editedAt)
                }
            } else {
                context.insert(try StoredPersonalReview(id: id, media: media, text: text, createdAt: now, viewingEventID: eventID, isLegacyImport: legacyEntryID != nil))
            }
            // Only an explicit successful edit/import clears the preserved legacy column.
            if legacyEntryID != nil { entry.review = nil }
        }
    }

    func deleteReview(_ id: UUID) throws {
        try writeDiary { context in
            if let review = try diaryReview(id, in: context) { context.delete(review) }
        }
    }

    func deleteLegacyReview(for id: MediaID) throws {
        try writeDiary { _ in
            // Ensure the caller acts on the same uniquely resolved title, never a sibling media type.
            if let record = try diaryLibraryEntry(for: id) { record.review = nil }
        }
    }

    func saveViewingEvent(id: UUID, media: MediaSearchResult, watchedDate: Date?, now: Date = .now) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              watchedDate?.timeIntervalSinceReferenceDate.isFinite != false else { throw DiaryError.invalidDate }
        let identity = SearchItem(media).id
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = watchedDate.map { calendar.startOfDay(for: $0) }
        try writeDiary { context in
            let existing = try diaryEvent(id, in: context)
            if let existing, existing.mediaID != identity { throw DiaryError.identityMismatch }
            _ = try ensureLibraryEntry(media: media)
            if let existing {
                if existing.watchedDate != date {
                    existing.watchedDate = date
                    existing.updatedAt = max(now, existing.updatedAt)
                }
            } else {
                context.insert(try StoredViewingEvent(id: id, media: media, watchedDate: date, recordedAt: now))
            }
        }
    }

    func deleteViewingEvent(_ id: UUID) throws {
        try writeDiary { context in
            guard let event = try diaryEvent(id, in: context) else { return }
            // Detach, never cascade-delete a written review when a watch is removed.
            let deletedEventID: UUID? = id
            let reviews = try context.fetch(FetchDescriptor<StoredPersonalReview>(predicate: #Predicate { $0.viewingEventID == deletedEventID }))
            for review in reviews { review.viewingEventID = nil }
            context.delete(event)
        }
    }

    private func diaryReview(_ id: UUID, in context: ModelContext) throws -> StoredPersonalReview? {
        var descriptor = FetchDescriptor<StoredPersonalReview>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func diaryEvent(_ id: UUID, in context: ModelContext) throws -> StoredViewingEvent? {
        var descriptor = FetchDescriptor<StoredViewingEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum DiaryError: Error, LocalizedError {
    case emptyReview, identityMismatch, eventUnavailable, eventHasReview, legacyChanged, invalidDate
    var errorDescription: String? {
        switch self {
        case .emptyReview: "Enter review text before saving."
        case .identityMismatch: "This record belongs to a different title. No changes were made."
        case .eventUnavailable: "The selected viewing or saved title is no longer available. Choose another viewing or no association."
        case .eventHasReview: "That viewing already has a review. Choose another viewing or no association."
        case .legacyChanged: "The earlier saved review has changed. Close this editor and reopen it before saving."
        case .invalidDate: "Choose a valid viewing date."
        }
    }
}

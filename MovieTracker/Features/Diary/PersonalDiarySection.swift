import SwiftUI

struct PersonalDiarySection: View {
    let media: MediaSearchResult
    @Environment(LibraryStore.self) private var library
    @State private var reviewDraft: ReviewDraft?
    @State private var eventDraft: ViewingEventDraft?
    @State private var deleteID: UUID?
    @State private var deletingLegacy = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    private var id: MediaID { SearchItem(media).id }

    var body: some View {
        DetailSection(title: "Your reviews and diary") {
            if let error = library.loadError { Text(error.localizedDescription).foregroundStyle(.secondary) }
            Button("Write Review") { reviewDraft = ReviewDraft(id: UUID(), media: media) }
                .accessibilityIdentifier("review.write")
            Button("Record Viewing") { eventDraft = ViewingEventDraft(id: UUID(), media: media) }
                .accessibilityIdentifier("diary.record")
            Text("\(library.events(for: id).count) viewing events. Open Viewing History in Library to edit individual viewings.")
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("diary.count")
            if library.reviews(for: id).isEmpty && library.entry(for: id)?.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                Text("No personal reviews yet.").foregroundStyle(.secondary)
            }
            if let entry = library.entry(for: id), let legacy = entry.review,
               !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    Text("Earlier saved review — original date unavailable").font(.subheadline)
                    Text(legacy).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Button("Edit Earlier Review") {
                        reviewDraft = ReviewDraft(id: UUID(), media: media, text: legacy, legacyEntryID: entry.id)
                    }
                    Button("Delete Earlier Review", role: .destructive) { deletingLegacy = true; confirmDelete = true }
                }
            }
            ForEach(library.reviews(for: id)) { review in
                PersonalReviewCard(review: review, edit: {
                    reviewDraft = ReviewDraft(id: review.id, media: media, text: review.text, viewingEventID: review.viewingEventID)
                }, delete: { deleteID = review.id; deletingLegacy = false; confirmDelete = true })
                if let eventID = review.viewingEventID, let event = library.viewingEvents.first(where: { $0.id == eventID }) {
                    Text("Associated viewing: " + event.dateLabel).font(.footnote)
                }
            }
        }
        .buttonStyle(.bordered)
        .sheet(item: $reviewDraft) { ReviewEditor(draft: $0) }
        .sheet(item: $eventDraft) { ViewingEventEditor(draft: $0) }
        .confirmationDialog("Delete this personal review?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Review", role: .destructive) {
                do {
                    if deletingLegacy { try library.deleteLegacyReview(for: id) }
                    else if let deleteID { try library.deleteReview(deleteID) }
                } catch { errorMessage = error.localizedDescription }
                deleteID = nil
            }
        } message: { Text("Viewing events, ratings and viewing status will be kept.") }
        .alert("Review change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
}

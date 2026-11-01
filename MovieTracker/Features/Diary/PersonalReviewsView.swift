import SwiftUI

/// Direct local access remains available even if a Library row was explicitly removed.
struct PersonalReviewsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var draft: ReviewDraft?
    @State private var deleting: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let error = library.loadError {
                Text(error.localizedDescription)
                Button("Retry Reviews") { library.reload() }
            }
            if library.personalReviews.isEmpty && !library.entries.contains(where: { $0.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) && library.loadError == nil {
                ContentUnavailableView("No personal reviews", systemImage: "text.bubble",
                                       description: Text("Write a private review from a movie or TV detail page."))
            }
            ForEach(library.personalReviews) { review in
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    if let id = review.mediaID {
                        NavigationLink(value: MediaDestination(id: id, title: review.savedTitle, year: nil)) {
                            Text(review.savedTitle).font(.headline)
                        }
                        Text(id.kind == .movie ? "Movie" : "TV Show").font(.subheadline)
                    }
                    PersonalReviewCard(review: review, edit: {
                        if let media = review.savedMedia {
                            draft = ReviewDraft(id: review.id, media: media, text: review.text, viewingEventID: review.viewingEventID)
                        }
                    }, delete: { deleting = review.id })
                }
            }
            ForEach(library.entries.filter { $0.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) { entry in
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    Text(entry.displayTitle).font(.headline)
                    Text("Earlier saved review — original date unavailable").font(.subheadline)
                    Text(entry.review ?? "").fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let media = entry.offlineMedia {
                        Button("Edit Earlier Review") { draft = ReviewDraft(id: UUID(), media: media, text: entry.review ?? "", legacyEntryID: entry.id) }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Personal Reviews")
        .sheet(item: $draft) { ReviewEditor(draft: $0) }
        .confirmationDialog("Delete this personal review?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Review", role: .destructive) {
                do { if let deleting { try library.deleteReview(deleting) } }
                catch { errorMessage = error.localizedDescription }
                deleting = nil
            }
        } message: { Text("Viewing events, ratings and viewing status will be kept.") }
        .alert("Review change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
}

struct PersonalReviewCard: View {
    let review: StoredPersonalReview
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(review.dateLabel)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(review.text).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .accessibilityIdentifier("review.text")
            Button("Edit Review", action: edit).buttonStyle(.bordered).accessibilityIdentifier("review.edit")
                .accessibilityLabel("Edit review, " + review.dateLabel)
            Button("Delete Review", role: .destructive, action: delete).buttonStyle(.bordered).accessibilityIdentifier("review.delete")
                .accessibilityLabel("Delete review, " + review.dateLabel)
        }
    }
}

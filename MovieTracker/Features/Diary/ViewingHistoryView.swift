import SwiftUI

struct ViewingHistoryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var editing: ViewingEventDraft?
    @State private var pendingDelete: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Newest first by watched date. Undated viewings use their date recorded. Ratings are your current overall title ratings.")
                    .font(.footnote)
                if let error = library.loadError {
                    Text(error.localizedDescription)
                    Button("Retry History") { library.reload() }
                }
            }
            if library.viewingEvents.isEmpty && library.loadError == nil {
                ContentUnavailableView("No viewings recorded", systemImage: "calendar",
                                       description: Text("Record a viewing from a movie or TV detail page."))
            }
            ForEach(library.viewingEvents) { event in
                if let id = event.mediaID {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        NavigationLink(value: MediaDestination(id: id, title: event.savedTitle, year: event.savedMedia.flatMap { SearchItem($0).year })) {
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                                Text(event.savedTitle).font(.headline)
                                Text(id.kind == .movie ? "Movie" : "TV Show").font(.subheadline)
                                Text(event.dateLabel).font(.subheadline)
                                PersonalRatingSummary(entry: library.entry(for: id))
                                if library.personalReviews.contains(where: { $0.viewingEventID == event.id }) {
                                    Label("Review for this viewing", systemImage: "text.bubble")
                                } else if !library.reviews(for: id).isEmpty || library.entry(for: id)?.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                    Label("Title review available", systemImage: "text.bubble")
                                }
                            }
                        }.accessibilityIdentifier("diary.row")
                        if let media = event.savedMedia {
                            Button("Edit Viewing") { editing = ViewingEventDraft(id: event.id, media: media, watchedDate: event.watchedDate, isNew: false) }
                                .buttonStyle(.bordered).accessibilityIdentifier("diary.edit")
                                .accessibilityLabel("Edit viewing for " + event.savedTitle + ", " + event.dateLabel)
                        }
                        Button("Delete Viewing", role: .destructive) { pendingDelete = event.id }
                            .buttonStyle(.bordered).accessibilityIdentifier("diary.delete")
                            .accessibilityLabel("Delete viewing for " + event.savedTitle + ", " + event.dateLabel)
                    }
                } else { Text(event.savedTitle + " — unknown media type") }
            }
        }
        .navigationTitle("Viewing History")
        .sheet(item: $editing) { ViewingEventEditor(draft: $0) }
        .confirmationDialog("Delete this viewing event?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Viewing", role: .destructive) {
                do { if let pendingDelete { try library.deleteViewingEvent(pendingDelete) } }
                catch { errorMessage = error.localizedDescription }
                pendingDelete = nil
            }
        } message: { Text("The title, its rating, reviews and other viewing events will be kept.") }
        .alert("Diary change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
}

import SwiftUI

struct ViewingHistoryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var editing: ViewingEventDraft?
    @State private var pendingDelete: UUID?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var textSize

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
                EmptyStateCard(title: "No viewings recorded", systemImage: "calendar",
                               message: "Record a viewing from a movie or TV detail page.", presentation: .inline)
                    .accessibilityIdentifier("history.empty")
            }
            ForEach(library.viewingEvents) { event in
                if let id = event.mediaID {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        NavigationLink(value: MediaDestination(id: id, title: event.savedTitle, year: event.savedMedia.flatMap { SearchItem($0).year })) {
                            Group {
                                if textSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                                        LibraryCachedPoster(url: library.entry(for: id)?.thumbnailURL)
                                        diaryDetails(event, id: id)
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                                        LibraryCachedPoster(url: library.entry(for: id)?.thumbnailURL)
                                        diaryDetails(event, id: id)
                                    }
                                }
                            }
                            .padding(.vertical, AppStyle.Spacing.small)
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
        .appListScreen("Viewing History")
        .accessibilityIdentifier("screen.history")
        .sheet(item: $editing) { ViewingEventEditor(draft: $0).appEditorSheet() }
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
    @ViewBuilder
    private func diaryDetails(_ event: StoredViewingEvent, id: MediaID) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(event.savedTitle).font(AppStyle.Typography.mediaTitle)
            Text(id.kind == .movie ? "Movie" : "TV Show").font(.subheadline)
            Text(event.dateLabel).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            PersonalRatingSummary(entry: library.entry(for: id))
            if library.hasReview(for: event.id) {
                Label("Review for this viewing", systemImage: "text.bubble")
            } else if !library.reviews(for: id).isEmpty || library.entry(for: id)?.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Label("Title review available", systemImage: "text.bubble")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

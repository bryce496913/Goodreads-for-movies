import SwiftUI

struct ReviewDraft: Identifiable {
    let id: UUID
    let media: MediaSearchResult
    var text = ""
    var viewingEventID: UUID?
    var legacyEntryID: UUID?
}

struct ReviewEditor: View {
    let draft: ReviewDraft
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var eventID: UUID?
    @State private var discard = false
    @State private var errorMessage: String?

    init(draft: ReviewDraft) {
        self.draft = draft
        _text = State(initialValue: draft.text)
        _eventID = State(initialValue: draft.viewingEventID)
    }
    private var hasChanges: Bool { text != draft.text || eventID != draft.viewingEventID }

    var body: some View {
        NavigationStack {
            Form {
                Text(SearchItem(draft.media).title).font(.headline)
                Text("Private review, stored only on this device.").font(.subheadline)
                TextEditor(text: $text).font(.body).frame(minHeight: 240)
                    .accessibilityLabel("Your private review").accessibilityIdentifier("review.editor")
                Picker("Associated viewing", selection: $eventID) {
                    Text("No associated viewing").tag(nil as UUID?)
                    ForEach(library.events(for: SearchItem(draft.media).id)) { event in
                        Text(event.dateLabel).tag(Optional(event.id))
                    }
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Enter review text before saving.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Personal Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { discard = true } else { dismiss() } }
                        .accessibilityIdentifier("review.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try library.saveReview(id: draft.id, media: draft.media, text: text,
                                                   eventID: eventID, legacyEntryID: draft.legacyEntryID)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("review.save")
                }
            }
            .confirmationDialog("Discard unsaved review changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .alert("Review could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Try again.") }
        }
        .interactiveDismissDisabled(hasChanges)
    }
}

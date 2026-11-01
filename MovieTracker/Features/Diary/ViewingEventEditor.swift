import SwiftUI

struct ViewingEventDraft: Identifiable {
    let id: UUID
    let media: MediaSearchResult
    var watchedDate: Date?
    var isNew = true
}

struct ViewingEventEditor: View {
    let draft: ViewingEventDraft
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var dateKnown: Bool
    @State private var date: Date
    @State private var discard = false
    @State private var errorMessage: String?

    init(draft: ViewingEventDraft) {
        self.draft = draft
        _dateKnown = State(initialValue: draft.watchedDate != nil)
        _date = State(initialValue: draft.watchedDate.map { DiaryDates.pickerDate(from: $0) } ?? .now)
    }
    private var hasChanges: Bool {
        dateKnown != (draft.watchedDate != nil) || (dateKnown && DiaryDates.storageDate(from: date) != draft.watchedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(SearchItem(draft.media).title).font(.headline)
                Toggle("Watched date known", isOn: $dateKnown).accessibilityIdentifier("diary.dateKnown")
                if dateKnown {
                    DatePicker("Watched date", selection: $date, displayedComponents: .date)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                } else {
                    Text("The watched date will remain unknown. History will label and sort this entry by its date recorded.")
                }
                if SearchItem(draft.media).id.kind == .tvShow {
                    Text("This logs a series viewing only. It does not complete or record any individual episodes.")
                }
                Text("Recording a viewing does not change your overall rating or viewing status.").font(.footnote)
            }
            .navigationTitle(draft.isNew ? "Record Viewing" : "Edit Viewing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try library.saveViewingEvent(id: draft.id, media: draft.media,
                                watchedDate: dateKnown ? DiaryDates.storageDate(from: date) : nil)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.accessibilityIdentifier("diary.save")
                }
            }
            .confirmationDialog("Discard unsaved viewing changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .alert("Viewing could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Try again.") }
        }
        .interactiveDismissDisabled(hasChanges)
    }
}

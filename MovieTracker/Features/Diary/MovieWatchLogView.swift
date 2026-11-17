import SwiftUI
import UIKit

@MainActor
struct MovieWatchLogView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var model: MovieWatchLogModel
    @State private var discard = false
    @FocusState private var editingReview: Bool
    @ScaledMetric(relativeTo: .body) private var reviewHeight: CGFloat = 160

    init(media: MediaSearchResult, rating: Result<PersonalRating?, Error>) {
        _model = State(initialValue: MovieWatchLogModel(media: media, rating: rating))
    }
    private var item: SearchItem {
        SearchItem(MetadataPolicy.forDisplay(model.media, at: max(library.metadataReferenceDate, Date.now)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { header }
                Section("When did you watch?") {
                    Toggle("Watched date known", isOn: $model.dateKnown).accessibilityIdentifier("watch.dateKnown")
                    if model.dateKnown {
                        DatePicker("Watched date", selection: $model.date, in: ...Date.now, displayedComponents: .date)
                            .environment(\.calendar, Calendar(identifier: .gregorian)).accessibilityIdentifier("watch.date")
                    } else {
                        Text("Undated viewing. History will label and sort it by when you recorded it.")
                            .font(AppStyle.Typography.caption)
                    }
                }
                Section {
                    PersonalRatingControl(current: { try model.currentRating() }, savesImmediately: false, save: { model.chooseRating($0) })
                    Text("This is your overall rating for the movie, not a rating for each watch. Unchanged ratings are kept. Changes apply only when you save this log.")
                        .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                }
                Section("Optional private review") {
                    Toggle("Add a review for this viewing", isOn: $model.writesReview).accessibilityIdentifier("watch.addReview")
                    if model.writesReview {
                        TextEditor(text: $model.review).font(AppStyle.Typography.body).frame(minHeight: reviewHeight)
                            .focused($editingReview).accessibilityLabel("Review for this viewing").accessibilityIdentifier("watch.review")
                    }
                    Text("A new review is linked only to this viewing. Earlier reviews are kept and never copied into a rewatch.")
                        .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                }
                Section {
                    Text("Saving creates one diary entry and marks this movie Watched. Favorites, collections and earlier viewings are kept.")
                        .font(AppStyle.Typography.caption)
                    if model.isSaving { AppLoadingState(title: "Saving watch…") }
                }
            }
            .appFormScreen("Log a Watch")
            .accessibilityIdentifier("screen.watchLog")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingReview = false }.accessibilityIdentifier("watch.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingReview = false
                        if model.hasChanges { discard = true } else { dismiss() }
                    }.disabled(model.isSaving).accessibilityIdentifier("watch.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editingReview = false
                        if model.save(into: library) {
                            dismiss()
                            UIAccessibility.post(notification: .announcement, argument: "Watch logged")
                        }
                    }.disabled(!model.canSave).accessibilityIdentifier("watch.save")
                }
            }
            .confirmationDialog("Discard this watch log?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: { Text("The viewing, rating and review have not been saved.") }
            .alert("Watch could not be saved", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
                Button("OK") { model.clearError() }
            } message: { Text(model.errorMessage ?? "Try again.") }
        }
        .interactiveDismissDisabled(model.hasChanges || model.isSaving)
    }
    private var poster: some View {
        LibraryCachedPoster(url: item.posterReference == nil ? nil : library.entry(for: item.id)?.thumbnailURL)
    }
    @ViewBuilder private var header: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) { poster; title }
        } else {
            HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { poster; title }
        }
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
            Text(item.year.map { "Movie · \($0)" } ?? "Movie").font(AppStyle.Typography.metadata)
        }
    }
}

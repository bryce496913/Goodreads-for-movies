import SwiftUI
import UIKit

struct CollectionDraft: Identifiable {
    let id: UUID
    var name: String
    var isNew = true
}

struct CollectionsSection: View {
    var preview = true
    @Environment(LibraryStore.self) private var library
    @State private var draft: CollectionDraft?
    var body: some View {
        Section("Collections") {
            if library.collections.isEmpty {
                EmptyStateCard(title: "Your private collections", systemImage: "folder", message: "Keep movies and shows together in lists you create. Adding a title never changes its viewing status.", presentation: .inline)
            }
            ForEach(preview ? Array(library.collections.prefix(3)) : library.collections) { collection in
                NavigationLink { CollectionContentsView(id: collection.id) } label: {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                        Text(collection.name).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                        Text("\(library.members(of: collection.id).count) \(library.members(of: collection.id).count == 1 ? "title" : "titles")").font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
                    }
                }.accessibilityIdentifier("collection.row." + collection.id.uuidString)
            }
            if preview && library.collections.count > 3 {
                NavigationLink("All Collections (\(library.collections.count))") { CollectionsLibraryView() }
            }
            Button("New Collection", systemImage: "folder.badge.plus") { draft = CollectionDraft(id: UUID(), name: "") }
                .buttonStyle(AppActionStyle()).accessibilityIdentifier("collection.create")
        }
        .sheet(item: $draft) { CollectionEditor(draft: $0).appEditorSheet() }
    }
}

private struct CollectionsLibraryView: View {
    var body: some View { List { CollectionsSection(preview: false) }.appListScreen("Collections") }
}

struct CollectionEditor: View {
    let draft: CollectionDraft
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?
    @State private var discard = false
    @FocusState private var editingName: Bool
    init(draft: CollectionDraft) { self.draft = draft; _name = State(initialValue: draft.name) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Collection name") {
                    TextField("Collection name", text: $name, axis: .vertical).focused($editingName).submitLabel(.done)
                        .onSubmit { editingName = false }
                        .accessibilityLabel("Collection name")
                        .accessibilityHint("Up to 100 characters. Names must be unique.")
                        .accessibilityIdentifier("collection.name")
                }
                Text("Private, on this device. Up to 100 characters; names must be unique regardless of capitalization.")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            }
            .appFormScreen(draft.isNew ? "New Collection" : "Rename Collection")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingName = false }.accessibilityIdentifier("collection.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if name != draft.name { discard = true } else { dismiss() } }.accessibilityIdentifier("collection.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if !draft.isNew && !library.collections.contains(where: { $0.id == draft.id }) { throw CollectionError.unavailable }
                            try library.saveCollection(id: draft.id, name: name)
                            dismiss()
                            UIAccessibility.post(notification: .announcement, argument: draft.isNew ? "Collection created" : "Collection renamed")
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled((try? CollectionName.validated(name)) == nil).accessibilityIdentifier("collection.save")
                }
            }
            .confirmationDialog("Discard collection name changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { editingName = true }
            }
            .alert("Collection could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Try again.") }
        }.interactiveDismissDisabled(name != draft.name)
    }
}

struct CollectionContentsView: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollectionDraft?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var editMode = EditMode.inactive
    @State private var removal: Removal?
    @State private var statusMessage: String?
    private struct Removal { let id: UUID; let title: String }
    private var owner: StoredCollection? { library.collections.first { $0.id == id } }
    var body: some View {
        List {
            if owner != nil {
                let rows = library.members(of: id)
                Section {
                    if rows.isEmpty {
                        EmptyStateCard(title: "This collection is empty", systemImage: "folder", message: "Use Add to List on a movie or show to include it here. Titles keep their Library status and rating.", presentation: .inline)
                    }
                    ForEach(rows) { row in
                        if let mediaID = row.mediaID { member(row, mediaID: mediaID, rows: rows) }
                    }
                    .onMove { source, destination in
                        var ids = rows.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        perform("Collection order saved") { try library.reorderCollection(id, memberships: ids, original: rows.map(\.id)) }
                    }
                } footer: {
                    Text(editMode.isEditing ? "Drag a reorder handle, or use a title’s actions to move it up or down." : "Your order is kept. Removing a title here affects this collection only.")
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle").font(AppStyle.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("collection.feedback")
                }
            } else {
                EmptyStateCard(title: "Collection unavailable", systemImage: "folder", message: "Return to Library to view your current lists.", presentation: .inline)
            }
        }
        .appListScreen(owner?.name ?? "Collection")
        .accessibilityIdentifier("screen.collection")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().disabled(owner == nil || library.members(of: id).count < 2)
                    .accessibilityLabel(editMode.isEditing ? "Finish reordering" : "Reorder titles")
                    .accessibilityIdentifier("collection.editOrder")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename Collection") { if let owner { draft = CollectionDraft(id: id, name: owner.name, isNew: false) } }
                        .accessibilityIdentifier("collection.rename")
                    Button("Delete Collection", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("collection.delete")
                } label: { Label("Collection actions", systemImage: "ellipsis.circle") }
                .disabled(owner == nil).accessibilityIdentifier("collection.actions")
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(item: $draft) { CollectionEditor(draft: $0).appEditorSheet() }
        .confirmationDialog("Remove from this collection?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible, presenting: removal) { selected in
            Button("Remove from Collection", role: .destructive) {
                perform("Removed from collection") { try library.removeCollectionMembers(id, memberships: [selected.id]) }
                removal = nil
            }
            Button("Keep in Collection", role: .cancel) { removal = nil }
        } message: { selected in
            Text("Remove “\(selected.title)” from this collection only? Your Library, rating, reviews, viewing history, progress and other collections are kept.")
        }
        .confirmationDialog("Delete this collection?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                do {
                    try library.deleteCollection(id); dismiss()
                    UIAccessibility.post(notification: .announcement, argument: "Collection deleted. Your titles and personal data are kept.")
                } catch { errorMessage = error.localizedDescription }
            }
            Button("Keep Collection", role: .cancel) { }
        } message: { Text("Only this list and its memberships will be removed. Titles, ratings, reviews, viewing history and episode progress are kept.") }
        .alert("Collection change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
    private func member(_ row: StoredCollectionMembership, mediaID: MediaID, rows: [StoredCollectionMembership]) -> some View {
        let route = destination(mediaID)
        return HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
            Group {
                if editMode.isEditing { CollectionMediaRow(id: mediaID) }
                else {
                    NavigationLink(value: route) { CollectionMediaRow(id: mediaID) }
                        .buttonStyle(.plain).accessibilityIdentifier("collection.member." + row.id.uuidString)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                moveActions(row, rows: rows)
                Button("Remove from Collection", role: .destructive) { removal = Removal(id: row.id, title: route.title) }
                    .accessibilityIdentifier("collection.remove." + row.id.uuidString)
            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: AppStyle.Layout.minimumTarget, minHeight: AppStyle.Layout.minimumTarget) }
            .buttonStyle(.borderless).accessibilityLabel("Actions for " + route.title)
            .accessibilityIdentifier("collection.memberActions." + row.id.uuidString)
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions { moveActions(row, rows: rows) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove from Collection", role: .destructive) { removal = Removal(id: row.id, title: route.title) }
        }
    }
    @ViewBuilder private func moveActions(_ row: StoredCollectionMembership, rows: [StoredCollectionMembership]) -> some View {
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            Button("Move Up") { move(row.id, offset: -1, rows: rows) }
                .disabled(index == 0).accessibilityIdentifier("collection.moveUp." + row.id.uuidString)
            Button("Move Down") { move(row.id, offset: 1, rows: rows) }
                .disabled(index == rows.count - 1).accessibilityIdentifier("collection.moveDown." + row.id.uuidString)
        }
    }
    private func move(_ membership: UUID, offset: Int, rows: [StoredCollectionMembership]) {
        guard let index = rows.firstIndex(where: { $0.id == membership }), rows.indices.contains(index + offset) else { return }
        var ordered = rows.map(\.id); ordered.swapAt(index, index + offset)
        perform("Collection order saved") { try library.reorderCollection(id, memberships: ordered, original: rows.map(\.id)) }
    }
    private func destination(_ id: MediaID) -> MediaDestination {
        let media = library.offlineMedia(for: id) ?? MetadataPolicy.placeholderMedia(id)
        let item = SearchItem(media)
        return MediaDestination(id: id, title: item.title, year: item.year)
    }
    private func perform(_ message: String, _ action: () throws -> Void) {
        statusMessage = nil
        do {
            try action(); statusMessage = message
            UIAccessibility.post(notification: .announcement, argument: message)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct CollectionMediaRow: View {
    let id: MediaID
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let media = library.offlineMedia(for: id) ?? MetadataPolicy.placeholderMedia(id)
        let item = SearchItem(media)
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) { poster; details(item) }
            } else {
                HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { poster; details(item) }
            }
        }.accessibilityElement(children: .combine)
    }
    private var poster: some View { LibraryCachedPoster(url: library.entry(for: id)?.thumbnailURL) }
    private func details(_ item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
            Text([item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
        }
    }
}

struct AddToCollectionAction: View {
    let media: MediaSearchResult
    @State private var presented = false
    var body: some View {
        Button("Add to List", systemImage: "folder.badge.plus") { presented = true }
            .buttonStyle(AppActionStyle(fillsWidth: true)).accessibilityIdentifier("collection.addToList")
            .sheet(isPresented: $presented) { CollectionMembershipPicker(media: media).appEditorSheet() }
    }
}

private struct CollectionMembershipPicker: View {
    let media: MediaSearchResult
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollectionDraft?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    var body: some View {
        NavigationStack {
            List {
                Text(SearchItem(media).title).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                Text("Changes save immediately. Lists do not change viewing status or rating.")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                if library.collections.isEmpty { Text("Create a private collection to start organizing your titles.") }
                ForEach(library.collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: {
                        library.isInCollection(collection.id, mediaID: SearchItem(media).id)
                    }, set: { selected in
                        statusMessage = nil
                        do {
                            try library.setCollectionMembership(selected, collection: collection.id, media: media)
                            let message = selected ? "Added to “\(collection.name)”" : "Removed from “\(collection.name)”"
                            statusMessage = message
                            UIAccessibility.post(notification: .announcement, argument: message)
                        } catch { errorMessage = error.localizedDescription }
                    })).accessibilityHint("Changes save immediately. Removing affects this collection only.")
                        .accessibilityIdentifier("collection.select." + collection.id.uuidString)
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle").font(AppStyle.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("collection.membershipFeedback")
                }
                Button("New Collection") { draft = CollectionDraft(id: UUID(), name: "") }
                    .buttonStyle(AppActionStyle()).accessibilityIdentifier("collection.create")
            }
            .appListScreen("Add to List")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("collection.done") } }
            .sheet(item: $draft) { CollectionEditor(draft: $0).appEditorSheet() }
            .alert("Membership could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Try again.") }
        }
    }
}

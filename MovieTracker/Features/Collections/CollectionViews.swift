import SwiftUI

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
            if library.collections.isEmpty { Text("Create private lists for movies and shows you want to keep together.").font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText) }
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
                TextField("Collection name", text: $name).focused($editingName).submitLabel(.done)
                    .onSubmit { editingName = false }.accessibilityIdentifier("collection.name")
                Text("Private, on this device. Up to 100 characters; names must be unique regardless of capitalization.")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            }
            .appFormScreen(draft.isNew ? "New Collection" : "Rename Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if name != draft.name { discard = true } else { dismiss() } }.accessibilityIdentifier("collection.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if !draft.isNew && !library.collections.contains(where: { $0.id == draft.id }) { throw CollectionError.unavailable }
                            try library.saveCollection(id: draft.id, name: name)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled((try? CollectionName.validated(name)) == nil).accessibilityIdentifier("collection.save")
                }
            }
            .confirmationDialog("Discard collection name changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
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
    private var owner: StoredCollection? { library.collections.first { $0.id == id } }
    var body: some View {
        List {
            if owner != nil {
                if library.members(of: id).isEmpty {
                    EmptyStateCard(title: "This collection is empty", systemImage: "folder", message: "Use Add to List on a movie or show to include it here.", presentation: .inline)
                }
                let rows = library.members(of: id)
                ForEach(rows) { row in
                    if let mediaID = row.mediaID {
                        NavigationLink(value: destination(mediaID)) {
                            CollectionMediaRow(id: mediaID)
                        }.accessibilityIdentifier("collection.member." + row.id.uuidString)
                    }
                }
                .onMove { source, destination in
                    var ids = rows.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    perform { try library.reorderCollection(id, memberships: ids, original: rows.map(\.id)) }
                }
                .onDelete { offsets in
                    perform { try library.removeCollectionMembers(id, memberships: Set(offsets.map { rows[$0].id })) }
                }
                Text("Remove affects this list only. Your Library, ratings, reviews and other lists stay unchanged.").font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)

            } else {
                EmptyStateCard(title: "Collection unavailable", systemImage: "folder", message: "Return to Library to view your current lists.", presentation: .inline)
            }
        }
        .appListScreen(owner?.name ?? "Collection")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("collection.editOrder") }
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
        .sheet(item: $draft) { CollectionEditor(draft: $0).appEditorSheet() }
        .confirmationDialog("Delete this collection?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                do { try library.deleteCollection(id); dismiss() } catch { errorMessage = error.localizedDescription }
            }
        } message: { Text("Only this list and its memberships will be removed. Titles, ratings, reviews, viewing history and episode progress are kept.") }
        .alert("Collection change failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Try again.") }
    }
    private func destination(_ id: MediaID) -> MediaDestination {
        let media = library.offlineMedia(for: id) ?? MetadataPolicy.placeholderMedia(id)
        let item = SearchItem(media)
        return MediaDestination(id: id, title: item.title, year: item.year)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { errorMessage = error.localizedDescription } }
}

private struct CollectionMediaRow: View {
    let id: MediaID
    @Environment(LibraryStore.self) private var library
    var body: some View {
        let media = library.offlineMedia(for: id) ?? MetadataPolicy.placeholderMedia(id)
        let item = SearchItem(media)
        HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
            LibraryCachedPoster(url: library.entry(for: id)?.thumbnailURL)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                Text(item.title).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                Text([item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            }
        }.accessibilityElement(children: .combine)
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
    var body: some View {
        NavigationStack {
            List {
                Text(SearchItem(media).title).font(AppStyle.Typography.mediaTitle)
                Text("Changes save immediately. Lists do not change viewing status or rating.")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
                if library.collections.isEmpty { Text("Create a private collection to start organizing your titles.") }
                ForEach(library.collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: {
                        library.isInCollection(collection.id, mediaID: SearchItem(media).id)
                    }, set: { selected in
                        do { try library.setCollectionMembership(selected, collection: collection.id, media: media) }
                        catch { errorMessage = error.localizedDescription }
                    })).accessibilityIdentifier("collection.select." + collection.id.uuidString)
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

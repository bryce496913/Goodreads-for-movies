import SwiftUI

struct WatchDiscoveryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WatchDiscoveryModel
    @FocusState private var editingYear: Bool

    private var request: WatchDiscoveryModel.Request { model.request(for: library) }
    private var ready: Bool { model.preparedRequest == request && !model.isUpdating }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section { Text(error); Button("Return to Library") { dismiss() } }
            } else if model.showingResult, let picked = model.picked {
                if model.preparedRequest?.source == request.source {
                    result(picked.retained(at: library.metadataReferenceDate))
                } else { ProgressView("Updating local choice…") }
            } else {
                sourceSection
                filterSection
                pickSection
            }
        }
        .appListScreen("What Should I Watch?")
        .accessibilityIdentifier("screen.discovery")
        .task(id: request) { await model.update(from: library, request: request) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingYear = false }.accessibilityLabel("Dismiss year keyboard")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { model.resetFlow() }.accessibilityIdentifier("discovery.reset")
            }
        }
    }

    private var sourceSection: some View {
        Section {
            Picker("Choose from", selection: $model.source) {
                Text("Watchlist").tag(DiscoverySource.watchlist)
                ForEach(library.collections) { collection in
                    Text(collection.name).tag(DiscoverySource.collection(collection.id))
                }
                if case .collection(let id) = model.source, !library.collections.contains(where: { $0.id == id }) {
                    Text("Collection unavailable").tag(DiscoverySource.collection(id))
                }
            }.accessibilityIdentifier("discovery.source")
            Text("A random choice from your own saved titles. Everything here works offline.")
                .font(.footnote).foregroundStyle(AppStyle.Colors.secondaryText)
        } header: { Text("Your next watch") }
    }

    private var filterSection: some View {
        Section {
            Picker("Media type", selection: $model.filters.media) {
                ForEach(LibraryMediaFilter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("discovery.media")
            if model.preparedRequest?.source.date == library.metadataReferenceDate, !model.genres.isEmpty || !model.filters.genres.isEmpty {
                DisclosureGroup("Genres — \(model.filters.genres.count) selected") {
                    ForEach(model.genres, id: \.id) { genre in
                        Toggle(genre.name, isOn: Binding(get: { model.filters.genres.contains(genre.id) }, set: { selected in
                            if selected { model.filters.genres.insert(genre.id) } else { model.filters.genres.remove(genre.id) }
                        })).accessibilityIdentifier("discovery.genre.\(genre.id)")
                    }
                    if !model.filters.genres.isEmpty { Button("Clear Genres") { model.filters.genres = [] } }
                    Text("Matches any selected genre. Genres come only from valid local metadata.").font(.footnote)
                }
            }
            yearControl("From year", value: $model.filters.firstYear, identifier: "discovery.firstYear")
            yearControl("Through year", value: $model.filters.lastYear, identifier: "discovery.lastYear")
            Picker("Movie runtime", selection: $model.filters.maximumMovieMinutes) {
                Text("Any length").tag(Int?.none)
                ForEach([90, 120, 150, 180], id: \.self) { value in Text("Up to \(value) minutes").tag(Optional(value)) }
            }.accessibilityIdentifier("discovery.runtime")
            Text("Runtime limits include movies only and exclude TV shows. Unknown or expired fields cannot match a filter that needs them. No metadata is downloaded here.")
                .font(.footnote).foregroundStyle(AppStyle.Colors.secondaryText)
            if !model.filters.isValid { Text("Enter years from 1 to 9999, with the first year no later than the last.").foregroundStyle(.red) }
            Button("Clear Filters") { model.resetFilters() }.accessibilityIdentifier("discovery.clearFilters")
        } header: { Text("Narrow it down") }
    }

    private func yearControl(_ label: String, value: Binding<Int?>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.subheadline)
            TextField("Any year", value: value, format: .number.grouping(.never))
                .keyboardType(.numbersAndPunctuation).submitLabel(.done).focused($editingYear)
                .onSubmit { editingYear = false }
                .accessibilityLabel(label).accessibilityIdentifier(identifier)
        }
    }

    private var pickSection: some View {
        Section {
            if !ready { ProgressView("Preparing local choices…") }
            else if model.sourceCount == 0 {
                EmptyStateCard(title: "Nothing to pick yet", systemImage: "sparkles", message: emptySourceMessage, presentation: .inline)
                Button("Return to Library") { dismiss() }
            } else if model.candidates.isEmpty {
                EmptyStateCard(title: "No matches", systemImage: "line.3.horizontal.decrease", message: "Try removing a filter. Titles with missing or expired metadata may not match.", presentation: .inline)
            } else {
                Text("\(model.candidates.count) eligible \(model.candidates.count == 1 ? "title" : "titles")")
                    .accessibilityIdentifier("discovery.count")
            }
            Button { model.pick(request: request) } label: { Label("Pick for Me", systemImage: "shuffle") }
                .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
                .disabled(!ready || model.candidates.isEmpty).accessibilityIdentifier("discovery.pick")
            if model.picked != nil {
                Button("Show Current Pick") { model.showingResult = true }.accessibilityIdentifier("discovery.current")
            }
        }
    }
    private var sourceName: String {
        switch model.source {
        case .watchlist: "Watchlist"
        case .collection(let id): library.collections.first(where: { $0.id == id })?.name ?? "Collection unavailable"
        }
    }
    private var emptySourceMessage: String {
        switch model.source {
        case .watchlist: "Add movies or shows to Watchlist from their details, or choose a collection."
        case .collection: "This collection has no titles available. Choose another source or add titles from their details."
        }
    }
    private func result(_ picked: DiscoveryCandidate) -> some View {
        Section {
            Text("Next pick from: \(sourceName)").font(.footnote).foregroundStyle(AppStyle.Colors.secondaryText)
            LibraryCachedPoster(url: picked.posterURL)
            Text(picked.item.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("discovery.result.title")
            Text([picked.item.mediaType, picked.item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
            if !picked.genres.isEmpty { Text(picked.genres.map(\.name).joined(separator: " · ")) }
            if let runtime = picked.movieMinutes { Text("\(runtime) minutes") }
            if !picked.metadataAvailable { Text("Saved identity is available offline. Details and artwork are unavailable locally.").font(.footnote) }
            NavigationLink(value: picked.item.destination) { Label("Open Details", systemImage: "info.circle") }
                .accessibilityIdentifier("discovery.details")
            Button("Pick Again") { model.pick(request: request) }
                .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
                .disabled(!ready || model.candidates.isEmpty).accessibilityIdentifier("discovery.again")
            if ready && model.candidates.isEmpty { Text("No more matches in the active source. Return to filters to adjust your choices.").font(.footnote) }
            Button("Return to Filters") { model.showingResult = false }.accessibilityIdentifier("discovery.filters")
        } header: { Text("Your pick") } footer: { Text("Picking never changes your Watchlist, rating, or viewing progress.") }
    }
}

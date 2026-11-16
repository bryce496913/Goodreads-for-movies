import SwiftUI
import UIKit

struct WatchDiscoveryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var textSize
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
                } else { AppLoadingState(title: "Updating local choice…") }
            } else {
                sourceSection
                pickSection
                filterSection
            }
        }
        .appListScreen("What Should I Watch?")
        .accessibilityIdentifier("screen.discovery")
        .task(id: request) { await model.update(from: library, request: request) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingYear = false }.accessibilityLabel("Dismiss year keyboard").accessibilityIdentifier("discovery.keyboardDone")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start Over") { editingYear = false; model.resetFlow() }.accessibilityIdentifier("discovery.reset")
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
            }.pickerStyle(.menu).accessibilityIdentifier("discovery.source")
            Text("A random choice from your own saved titles. Everything here works offline.")
                .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
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
                    if !model.filters.genres.isEmpty {
                        Button("Clear Genres") { model.filters.genres = [] }.buttonStyle(AppActionStyle(emphasis: .tertiary))
                    }
                    Text("Matches any selected genre.").font(AppStyle.Typography.caption)
                }
            }
            yearControl("From year", value: $model.filters.firstYear, identifier: "discovery.firstYear")
            yearControl("Through year", value: $model.filters.lastYear, identifier: "discovery.lastYear")
            Picker("Movie runtime", selection: $model.filters.maximumMovieMinutes) {
                Text("Any length").tag(Int?.none)
                ForEach([90, 120, 150, 180], id: \.self) { value in Text("Up to \(value) minutes").tag(Optional(value)) }
            }.accessibilityIdentifier("discovery.runtime")
            Text("Runtime limits include movies only and exclude TV shows.")
                .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            if !model.filters.isValid {
                AppErrorMessage(message: "Enter years from 1 to 9999, with the first year no later than the last.")
                    .accessibilityIdentifier("discovery.invalidYears")
            }
            Button("Clear Filters") { editingYear = false; model.resetFilters() }
                .buttonStyle(AppActionStyle(emphasis: .tertiary)).accessibilityIdentifier("discovery.clearFilters")
        } header: { Text("Narrow it down") } footer: {
            Text("Unknown or expired fields cannot match a filter that needs them. Only saved local metadata is used; nothing is downloaded here.")
        }
    }

    private func yearControl(_ label: String, value: Binding<Int?>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(AppStyle.Typography.metadata)
            TextField("Any year", value: value, format: .number.grouping(.never))
                .keyboardType(.numbersAndPunctuation).submitLabel(.done).focused($editingYear)
                .frame(minHeight: AppStyle.Layout.minimumTarget)
                .onSubmit { editingYear = false }
                .accessibilityLabel(label).accessibilityIdentifier(identifier)
        }
    }

    private var pickSection: some View {
        Section {
            if !ready { AppLoadingState(title: "Preparing local choices…") }
            else if model.sourceCount == 0 {
                EmptyStateCard(title: "Nothing to pick yet", systemImage: "sparkles", message: emptySourceMessage, presentation: .inline)
                Button("Return to Library") { dismiss() }
            } else {
                Text("\(model.candidates.count) eligible \(model.candidates.count == 1 ? "title" : "titles")")
                    .font(AppStyle.Typography.mediaTitle).accessibilityIdentifier("discovery.count")
                if model.candidates.isEmpty {
                    EmptyStateCard(title: "No matches", systemImage: "line.3.horizontal.decrease", message: "Try removing a filter. Titles with missing or expired metadata may not match.", presentation: .inline)
                }
            }
            Button { pick() } label: { Label("Pick for Me", systemImage: "shuffle") }
                .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
                .disabled(!ready || model.candidates.isEmpty).accessibilityIdentifier("discovery.pick")
            if model.picked != nil {
                Button("Show Current Pick") { editingYear = false; model.showingResult = true }
                    .buttonStyle(AppActionStyle(emphasis: .tertiary, fillsWidth: true)).accessibilityIdentifier("discovery.current")
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
            Text("Next pick from: \(sourceName)").font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            resultSummary(picked)
            if !picked.metadataAvailable {
                Text("Your saved title is available by its ID. More details and artwork are not available locally.")
                    .font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            }
            NavigationLink(value: picked.item.destination) { Label("Open Details", systemImage: "info.circle") }
                .buttonStyle(AppActionStyle(fillsWidth: true)).accessibilityIdentifier("discovery.details")
            Button("Pick Again") { pick() }
                .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
                .disabled(!ready || model.candidates.isEmpty).accessibilityIdentifier("discovery.again")
            if ready && model.candidates.isEmpty {
                Text("No titles currently match the active source and filters. Return to filters to adjust your choices.").font(AppStyle.Typography.caption)
            }
            Button("Return to Filters") { model.showingResult = false }
                .buttonStyle(AppActionStyle(emphasis: .tertiary, fillsWidth: true)).accessibilityIdentifier("discovery.filters")
        } header: { Text("Your pick") } footer: { Text("Picking never changes your Watchlist, rating, or viewing progress.") }
    }
    @ViewBuilder private func resultSummary(_ picked: DiscoveryCandidate) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                LibraryCachedPoster(url: picked.posterURL)
                resultMetadata(picked)
            }
        } else {
            HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                LibraryCachedPoster(url: picked.posterURL)
                resultMetadata(picked)
            }
        }
    }
    private func resultMetadata(_ picked: DiscoveryCandidate) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(picked.item.title).font(AppStyle.Typography.sectionHeading).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("discovery.result.title")
            Text([picked.item.mediaType, picked.item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                .font(AppStyle.Typography.metadata)
            if !picked.genres.isEmpty { Text(picked.genres.map(\.name).joined(separator: " · ")).font(AppStyle.Typography.metadata) }
            if let runtime = picked.movieMinutes { Text("\(runtime) minutes").font(AppStyle.Typography.metadata) }
        }.foregroundStyle(AppStyle.Colors.primaryText)
    }
    private func pick() {
        guard ready, !model.candidates.isEmpty else { return }
        editingYear = false
        model.pick(request: request)
        if let picked = model.picked {
            UIAccessibility.post(notification: .announcement, argument: "Your pick: \(picked.item.title), \(picked.item.mediaType)")
        }
    }
}

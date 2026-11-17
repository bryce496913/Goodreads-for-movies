import SwiftUI

struct ViewingHistoryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var editing: ViewingEventDraft?
    @State private var pendingDelete: UUID?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.calendar) private var userCalendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var calendarModel = ViewingCalendarModel()
    @State private var presentation = HistoryPresentation.list
    @State private var undatedOnly = false
    private enum HistoryPresentation: String, CaseIterable, Identifiable {
        case list = "List", calendar = "Calendar"
        var id: Self { self }
    }
    private var source: ViewingCalendarModel.Source {
        var calendar = userCalendar
        let first = calendar.firstWeekday
        calendar.locale = locale; calendar.timeZone = timeZone; calendar.firstWeekday = first
        return .init(revision: library.revision, calendar: calendar, locale: locale)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    if textSize.isAccessibilitySize { historyPicker.pickerStyle(.menu) }
                    else { historyPicker.pickerStyle(.segmented) }
                    if let error = library.loadError {
                        Text(error.localizedDescription)
                        Button("Retry History") { library.reload() }
                    }
                    if let error = calendarModel.errorMessage { AppErrorMessage(message: error) }
                }
                if presentation == .list {
                    Section {
                        Text("Newest first by watched date. Undated viewings use their date recorded. Ratings are your current overall title ratings.")
                            .font(AppStyle.Typography.caption)
                        Toggle("Undated only", isOn: $undatedOnly).accessibilityIdentifier("history.undatedOnly")
                    }
                    if library.viewingEvents.isEmpty && library.loadError == nil {
                        EmptyStateCard(title: "No viewings recorded", systemImage: "calendar",
                            message: "Log a watch from a movie, or record a viewing from a TV detail page.", presentation: .inline)
                            .accessibilityIdentifier("history.empty")
                    } else if undatedOnly && calendarModel.errorMessage != nil {
                        Text("Reopen Viewing History to retry.")
                    } else if undatedOnly && !calendarModel.isReady(for: source) {
                        AppLoadingState(title: "Updating viewings…")
                    } else {
                        let events = undatedOnly ? calendarModel.undatedEvents : library.viewingEvents
                        if undatedOnly && events.isEmpty && library.loadError == nil { Text("No undated viewings").accessibilityIdentifier("history.noUndated") }
                        ForEach(events) { event in eventRow(event) }
                    }
                } else {
                    ViewingMonthView(model: calendarModel, ready: calendarModel.isReady(for: source)) { day in
                        calendarModel.select(day)
                        proxy.scrollTo("calendar.events", anchor: .top)
                    }
                    Section {
                        Text("Only watched dates appear on the calendar. Undated viewings are kept in List; their recorded dates are never substituted.")
                            .font(AppStyle.Typography.caption)
                        if calendarModel.index.unavailableDates > 0 {
                            Text("\(calendarModel.index.unavailableDates) dated viewings cannot be represented in this time zone. Their saved dates are kept in List.").font(AppStyle.Typography.caption)
                            Button("Show All in List") { undatedOnly = false; presentation = .list }.buttonStyle(AppActionStyle(emphasis: .tertiary))
                        }
                        Button("Show Undated in List (\(calendarModel.index.undated.count))") { undatedOnly = true; presentation = .list }
                            .buttonStyle(AppActionStyle(emphasis: .tertiary)).accessibilityIdentifier("calendar.undated")
                    }
                    Section {
                        if calendarModel.errorMessage != nil {
                            Text("Reopen Viewing History to retry.")
                        } else if !calendarModel.isReady(for: source) {
                            AppLoadingState(title: "Updating calendar…")
                        } else if calendarModel.selectedEvents.isEmpty && library.loadError == nil {
                            EmptyStateCard(title: "No viewings on this day", systemImage: "calendar", message: "Choose a day with a viewing count, or explore another month.", presentation: .inline)
                                .accessibilityIdentifier("calendar.emptyDay")
                        } else {
                            ForEach(calendarModel.selectedEvents) { event in eventRow(event) }
                        }
                    } header: {
                        Text(ViewingCalendarProjection.label(calendarModel.selectedDay, calendar: calendarModel.calendar, locale: locale))
                            .id("calendar.events").accessibilityIdentifier("calendar.selectedDay")
                    }
                }
            }
        }
        .appListScreen("Viewing History")
        .accessibilityIdentifier("screen.history")
        .task(id: source) { await calendarModel.update(library.viewingEvents, source: source) }
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
    @ViewBuilder private func eventRow(_ event: StoredViewingEvent) -> some View {
        if let id = event.mediaID {
            let label = dateLabel(event)
            let media = MetadataPolicy.forDisplay(event.savedMedia ?? MetadataPolicy.placeholderMedia(id), at: max(library.metadataReferenceDate, Date.now))
            let item = SearchItem(media)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                NavigationLink(value: item.destination) {
                    Group {
                        if textSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) { LibraryCachedPoster(url: item.posterReference == nil ? nil : library.entry(for: id)?.thumbnailURL); diaryDetails(event, id: id, label: label, item: item) }
                        } else {
                            HStack(alignment: .top, spacing: AppStyle.Spacing.medium) { LibraryCachedPoster(url: item.posterReference == nil ? nil : library.entry(for: id)?.thumbnailURL); diaryDetails(event, id: id, label: label, item: item) }
                        }
                    }.padding(.vertical, AppStyle.Spacing.small)
                }.buttonStyle(.plain).accessibilityIdentifier("diary.row")
                Button("Edit Viewing") { editing = ViewingEventDraft(id: event.id, media: media, watchedDate: event.watchedDate, isNew: false) }
                    .buttonStyle(AppActionStyle()).accessibilityIdentifier("diary.edit")
                    .accessibilityLabel("Edit viewing for " + item.title + ", " + label)
                Button("Delete Viewing", role: .destructive) { pendingDelete = event.id }
                    .appDestructiveAction().accessibilityIdentifier("diary.delete")
                    .accessibilityLabel("Delete viewing for " + item.title + ", " + label)
            }
        } else { Text(event.savedTitle + " — unknown media type") }
    }
    @ViewBuilder
    private func diaryDetails(_ event: StoredViewingEvent, id: MediaID, label: String, item: SearchItem) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(item.title).font(AppStyle.Typography.mediaTitle)
            Text([item.mediaType, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")).font(AppStyle.Typography.metadata)
            Text(label).font(AppStyle.Typography.metadata).foregroundStyle(AppStyle.Colors.secondaryText)
            if event.watchedDate != nil {
                Text("Recorded: " + recordedLabel(event.recordedAt)).font(AppStyle.Typography.caption).foregroundStyle(AppStyle.Colors.secondaryText)
            }
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

    private var historyPicker: some View {
        Picker("History display", selection: $presentation) {
            ForEach(HistoryPresentation.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("history.display")
    }
    private func dateLabel(_ event: StoredViewingEvent) -> String {
        if let watched = event.watchedDate {
            if let date = ViewingCalendarProjection.day(for: watched, calendar: source.calendar) {
                return "Watched " + ViewingCalendarProjection.label(date, calendar: source.calendar, locale: locale)
            }
            return event.dateLabel + " — day unavailable in this time zone"
        }
        return "Date recorded " + recordedLabel(event.recordedAt)
    }
    private func recordedLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = source.calendar; formatter.locale = locale; formatter.timeZone = timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}

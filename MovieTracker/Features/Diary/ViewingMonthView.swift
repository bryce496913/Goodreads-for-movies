import SwiftUI
import UIKit

struct ViewingMonthView: View {
    let model: ViewingCalendarModel
    let ready: Bool
    let select: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    private let columns = Array(repeating: GridItem(.flexible(minimum: AppStyle.Layout.minimumTarget), spacing: AppStyle.Spacing.xSmall), count: 7)
    var body: some View {
        Section {
            HStack {
                Button { model.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: AppStyle.Layout.minimumTarget, minHeight: AppStyle.Layout.minimumTarget) }
                    .accessibilityLabel("Previous month").accessibilityIdentifier("calendar.previous")
                Text(model.month.title).font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader).accessibilityIdentifier("calendar.month")
                Button { model.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(minWidth: AppStyle.Layout.minimumTarget, minHeight: AppStyle.Layout.minimumTarget) }
                    .accessibilityLabel("Next month").accessibilityIdentifier("calendar.next")
            }.buttonStyle(.borderless)
            Button("Today") { model.today() }.buttonStyle(AppActionStyle(emphasis: .tertiary)).accessibilityIdentifier("calendar.today")
            if textSize.isAccessibilitySize {
                ForEach(model.month.days, id: \.self) { day in dayButton(day, expanded: true) }
            } else {
                ScrollView(.horizontal) {
                    LazyVGrid(columns: columns, spacing: AppStyle.Spacing.xSmall) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(model.month.weekdays[index]).font(AppStyle.Typography.caption).frame(minHeight: AppStyle.Layout.minimumTarget).accessibilityHidden(true)
                        }
                        ForEach(model.month.slots.indices, id: \.self) { index in
                            if let day = model.month.slots[index] { dayButton(day, expanded: false) }
                            else { Color.clear.frame(minHeight: AppStyle.Layout.minimumTarget).accessibilityHidden(true) }
                        }
                    }.frame(minWidth: 7 * AppStyle.Layout.minimumTarget + 6 * AppStyle.Spacing.xSmall)
                }.accessibilityHint("Scroll horizontally if not all weekday columns are visible.")
            }
        } header: { Text("Viewing Calendar") }
    }
    private func dayButton(_ date: Date, expanded: Bool) -> some View {
        let count = ready ? model.index.days[date]?.count ?? 0 : 0
        let selected = model.selectedDay == date
        let label = model.month.labels[date] ?? ViewingCalendarProjection.label(date, calendar: model.calendar, locale: model.locale)
        let number = model.calendar.component(.day, from: date).formatted(.number.locale(model.locale))
        return Button {
            select(date)
            UIAccessibility.post(notification: .announcement, argument: "\(label), \(count) viewing events")
        } label: {
            VStack(spacing: AppStyle.Spacing.xSmall) {
                Text(expanded ? label : number).font(AppStyle.Typography.metadata)
                if count > 0 { Label("\(count)", systemImage: "film").font(AppStyle.Typography.caption) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: AppStyle.Layout.minimumTarget, maxWidth: .infinity, minHeight: AppStyle.Layout.minimumTarget).padding(.vertical, AppStyle.Spacing.xSmall)
            .foregroundStyle(selected ? AppStyle.Colors.onAccent : AppStyle.Colors.primaryText)
            .background(selected ? AppStyle.Colors.accent : AppStyle.Colors.surface, in: RoundedRectangle(cornerRadius: AppStyle.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: AppStyle.Radius.control).strokeBorder(AppStyle.Colors.divider) }
        }
        .buttonStyle(.plain).disabled(!ready).accessibilityLabel("\(label), \(count) viewing events")
        .accessibilityValue(ready ? (selected ? "Selected" : "Not selected") : "Updating viewings")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(model.calendar.component(.day, from: date))")
    }
}

import SwiftUI

struct EmptyStateCard: View {
    enum Presentation { case card, inline }
    let title: String
    let systemImage: String
    let message: String
    var presentation: Presentation = .card

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.small) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(AppStyle.Colors.accent).accessibilityHidden(true)
                Text(title).font(AppStyle.Typography.sectionHeading).foregroundStyle(AppStyle.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(AppStyle.Typography.body)
                .foregroundStyle(AppStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(presentation == .card ? AppStyle.Spacing.medium : 0)
        .background(presentation == .card ? AppStyle.surface : Color.clear, in: RoundedRectangle(cornerRadius: AppStyle.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: AppStyle.Radius.card).strokeBorder(presentation == .card ? AppStyle.Colors.divider : .clear, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

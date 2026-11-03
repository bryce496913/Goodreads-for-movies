import SwiftUI

struct EmptyStateCard: View {
    let title: String
    let systemImage: String
    let message: String

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
        .padding(AppStyle.Spacing.medium)
        .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: AppStyle.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: AppStyle.Radius.card).strokeBorder(AppStyle.Colors.divider, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

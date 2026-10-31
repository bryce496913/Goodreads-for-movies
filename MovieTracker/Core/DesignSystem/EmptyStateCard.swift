import SwiftUI

struct EmptyStateCard: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppStyle.Spacing.medium)
        .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

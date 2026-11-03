import SwiftUI

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppStyle.Typography.sectionHeading)
            .foregroundStyle(AppStyle.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

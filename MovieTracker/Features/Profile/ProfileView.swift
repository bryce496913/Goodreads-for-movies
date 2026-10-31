import SwiftUI

struct ProfileView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                EmptyStateCard(
                    title: "Your viewing story", systemImage: "person.crop.circle",
                    message: "A personal space for your movie and TV journey. No account is needed."
                )
                VStack(spacing: AppStyle.Spacing.medium) {
                    SectionHeading(title: "Viewing statistics")
                    EmptyStateCard(
                        title: "Every story starts somewhere", systemImage: "chart.bar",
                        message: "Viewing statistics will appear here as tracking features become available."
                    )
                }
                NavigationLink {
                    ContentUnavailableView(
                        "Settings coming soon",
                        systemImage: "gearshape",
                        description: Text("Preferences will be available in a future update.")
                    )
                    .navigationTitle("Settings")
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppStyle.Spacing.medium)
                        .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.settings")
            }
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Profile")
    }
}

import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
                Text("A home for everything you watch.")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: AppStyle.Spacing.medium) {
                    SectionHeading(title: "Up next")
                    EmptyStateCard(
                        title: "Your next watch starts here",
                        systemImage: "play.rectangle",
                        message: "As you build your library, upcoming viewing activity will appear here."
                    )
                }
                VStack(spacing: AppStyle.Spacing.medium) {
                    SectionHeading(title: "For you")
                    EmptyStateCard(
                        title: "More to discover",
                        systemImage: "sparkles",
                        message: "Movie and TV recommendations are planned for a future update."
                    )
                }
            }
            .padding(AppStyle.Spacing.medium)
        }
        .background(AppStyle.background)
        .navigationTitle("Welcome")
    }
}

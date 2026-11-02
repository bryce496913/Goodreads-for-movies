import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("MovieTracker Beta") {
                Text("A private movie and television diary stored on this device.")
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable"))")
                Text("No accounts, cloud synchronization, public reviews or analytics. Removing the app removes its local data.")
            }
            Section("Metadata Credits") {
                Image("TMDBLogo").resizable().scaledToFit().frame(maxWidth: 160)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("The Movie Database logo")
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .accessibilityIdentifier("credits.tmdbNotice")
                if let url = URL(string: "https://www.themoviedb.org") { Link("The Movie Database (TMDB)", destination: url) }
                Text("Search queries and requested title identifiers are sent to TMDB when retrieving metadata. Artwork loads from TMDB’s image service. Your ratings, reviews, diary and watched flags remain local.")
                Text("Discovery and uncached metadata need a connection and authorized provider configuration. Saved text and progress remain available offline; artwork may be missing when the system cache is unavailable.")
            }
        }
        .navigationTitle("About & Credits")
    }
}

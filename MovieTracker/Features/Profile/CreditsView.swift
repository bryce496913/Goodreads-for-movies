import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("About This Beta") {
                PageHeader(title: "MovieTracker Beta", subtitle: "A private movie and television diary stored on this device.")
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable"))")
                Text("No accounts, cloud synchronization, public reviews or analytics. Removing the app removes its local data.")
            }
            Section("Metadata Credits") {
                Image("TMDBLogo").resizable().scaledToFit().frame(maxWidth: 160)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("The Movie Database logo").accessibilityIdentifier("credits.tmdbLogo")
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .accessibilityIdentifier("credits.tmdbNotice")
                if let url = URL(string: "https://www.themoviedb.org") { Link("The Movie Database (TMDB)", destination: url) }
                Text("Search queries and requested title identifiers are sent to TMDB when retrieving metadata. Artwork loads from TMDB’s image service. Your ratings, reviews, diary and watched flags remain local.")
                Text("Your ratings, private review text, diary and watched flags remain local. Provider titles, descriptions and dates expire after 150 days; a refresh becomes eligible after 30 days. Missing or expired metadata uses an identifier placeholder, including offline. Artwork is held only in bounded memory and can disappear at any time.").accessibilityIdentifier("credits.cachePolicy")
                Text("This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.")
            }
        }
        .appListScreen("About & Credits")
        .accessibilityIdentifier("screen.credits")
    }
}

import SwiftUI

struct AppRootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "books.vertical") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}

#Preview {
    AppRootView()
}

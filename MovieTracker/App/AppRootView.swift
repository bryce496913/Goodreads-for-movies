import SwiftData
import SwiftUI

private enum RootTab: Hashable { case home, search, library, profile }

struct AppRootView: View {
    @State private var tab: RootTab = .home
    @State private var searchPath = NavigationPath()
    @State private var searchModel = SearchLaunchConfiguration.makeModel()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }.tag(RootTab.home)
            NavigationStack(path: $searchPath) { SearchView(model: searchModel) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(RootTab.search)
            NavigationStack {
                LibraryView(detailModel: { destination, savedMedia in searchModel.detailModel(for: destination, savedMedia: savedMedia) },
                            openSearch: { searchPath = NavigationPath(); tab = .search })
            }
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(RootTab.library)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person") }.tag(RootTab.profile)
        }
    }
}

#Preview {
    if let container = try? PersistenceController.makeContainer(inMemory: true) {
        AppRootView().environment(LibraryStore(container: container)).modelContainer(container)
    }
}

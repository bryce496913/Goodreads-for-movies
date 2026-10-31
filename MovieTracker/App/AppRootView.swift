import SwiftData
import SwiftUI

struct AppRootView: View {
    @State private var searchModel = SearchLaunchConfiguration.makeModel()

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SearchView(model: searchModel) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView { destination, savedMedia in searchModel.detailModel(for: destination, savedMedia: savedMedia) } }
                .tabItem { Label("Library", systemImage: "books.vertical") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}

#Preview {
    if let container = try? PersistenceController.makeContainer(inMemory: true) {
        AppRootView().environment(LibraryStore(container: container)).modelContainer(container)
    }
}

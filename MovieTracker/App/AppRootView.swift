import SwiftData
import SwiftUI

private enum RootTab: Hashable { case home, search, library, profile }

struct AppRootView: View {
    @State private var tab: RootTab = .home
    @State private var searchPath = NavigationPath()
    @State private var searchModel = SearchLaunchConfiguration.makeModel()

    @State private var dashboard = DashboardModel()
    @State private var organization = LibraryOrganizationModel()
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundRevision = 0
    private struct RefreshKey: Hashable { let revision: Int; let foreground: Int }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView(dashboard: dashboard, progressModel: { searchModel.tvProgressModel(for: $0) },
                         openSearch: openSearch, openLibrary: { organization.resetFilters(); tab = .library })
                    .modifier(SavedMediaNavigation(detailModel: { searchModel.detailModel(for: $0, savedMedia: $1) }))
            }
                .tabItem { Label("Home", systemImage: "house") }.tag(RootTab.home)
            NavigationStack(path: $searchPath) { SearchView(model: searchModel) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(RootTab.search)
            NavigationStack {
                LibraryView(detailModel: { destination, savedMedia in searchModel.detailModel(for: destination, savedMedia: savedMedia) },
                            openSearch: openSearch, organization: organization)
            }
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(RootTab.library)
            NavigationStack {
                ProfileView(dashboard: dashboard)
                    .modifier(SavedMediaNavigation(detailModel: { searchModel.detailModel(for: $0, savedMedia: $1) }))
            }
                .tabItem { Label("Profile", systemImage: "person") }.tag(RootTab.profile)
        }
        .task(id: RefreshKey(revision: library.revision, foreground: foregroundRevision)) {
            let now = Date.now
            guard library.loadError == nil, dashboard.needsRefresh(revision: library.revision, now: now) else { return }
            await dashboard.refresh(DashboardInput.capture(library), revision: library.revision, now: now)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { foregroundRevision += 1 } }
    }
    private func openSearch() { searchPath = NavigationPath(); tab = .search }
}

#Preview {
    if let container = try? PersistenceController.makeContainer(inMemory: true) {
        AppRootView().environment(LibraryStore(container: container)).modelContainer(container)
    }
}

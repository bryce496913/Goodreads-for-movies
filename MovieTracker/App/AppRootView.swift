import SwiftData
import SwiftUI

struct AppRootView: View {
    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var searchModel = SearchLaunchConfiguration.makeModel()

    @State private var dashboard = DashboardModel()
    @State private var organization = LibraryOrganizationModel()
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundRevision = 0
    private struct RefreshKey: Hashable { let revision: Int; let foreground: Int }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) {
                HomeView(dashboard: dashboard, progressModel: { searchModel.tvProgressModel(for: $0) },
                         openSearch: openSearch, openLibrary: openLibrary)
                    .modifier(SavedMediaNavigation(detailModel: { searchModel.detailModel(for: $0, savedMedia: $1) }))
            }
                .appTabChrome()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }.tag(AppTab.home)
            NavigationStack(path: $searchPath) { SearchView(model: searchModel) }
                .appTabChrome()
                .tabItem { Label(AppTab.search.title, systemImage: AppTab.search.symbol) }.tag(AppTab.search)
            NavigationStack(path: $libraryPath) {
                LibraryView(detailModel: { destination, savedMedia in searchModel.detailModel(for: destination, savedMedia: savedMedia) },
                            openSearch: openSearch, organization: organization, openSection: { libraryPath.append($0) })
            }
                .appTabChrome()
                .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.symbol) }.tag(AppTab.library)
            NavigationStack(path: $profilePath) {
                ProfileView(dashboard: dashboard, configurationChanged: {
                    MetadataRuntimeGate.credentialEpoch += 1
                    try? library.clearMetadataBackoff()
                    if (try? SearchLaunchConfiguration.credentialStorage().read()) == nil {
                        try? library.clearProviderMetadata(); searchModel.clearProviderSession()
                    } else { library.metadataInvalidation += 1 }
                    SearchLaunchConfiguration.reconfigure(searchModel)
                })
                    .modifier(SavedMediaNavigation(detailModel: { searchModel.detailModel(for: $0, savedMedia: $1) }))
            }
                .appTabChrome()
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.symbol) }.tag(AppTab.profile)
        }
        .tint(AppStyle.Colors.accent)
        .task(id: RefreshKey(revision: library.revision, foreground: foregroundRevision)) {
            let now = Date.now
            guard library.loadError == nil, dashboard.needsRefresh(revision: library.revision, now: now) else { return }
            await dashboard.refresh(DashboardInput.capture(library), revision: library.revision, now: now)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    try library.maintainMetadata()
                    ProviderArtworkCache.shared.expire(at: library.metadataReferenceDate)
                    searchModel.expireMetadata(at: library.metadataReferenceDate)
                    await searchModel.expireProviderMemory(at: library.metadataReferenceDate)
                    foregroundRevision += 1
                    try await Task.sleep(for: .seconds(60))
                } catch is CancellationError { return }
                catch { library.metadataWarning = "Metadata cleanup could not be saved. Preserve your personal data and retry."; return }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { foregroundRevision += 1 } }
    }
    private func openLibrary() { libraryPath = NavigationPath(); organization.resetFilters(); tab = .library }
    private func openSearch() { searchPath = NavigationPath(); tab = .search }
}

#Preview {
    if let container = try? PersistenceController.makeContainer(inMemory: true) {
        AppRootView().environment(LibraryStore(container: container)).modelContainer(container)
    }
}

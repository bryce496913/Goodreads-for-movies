import SwiftUI

/// Presentation metadata only; navigation remains four native stacks owned by AppRootView.
enum AppTab: CaseIterable, Hashable {
    case home, search, library, profile
    var title: String {
        switch self { case .home: "Home"; case .search: "Search"; case .library: "Library"; case .profile: "Profile" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .search: "magnifyingglass"; case .library: "books.vertical"; case .profile: "person.crop.circle" }
    }
}

extension View {
    /// Native large root titles; pushed pages and modal editors use inline titles.
    func appPageTitle(_ title: String, isRoot: Bool = false) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
            .toolbarBackground(AppStyle.background, for: .navigationBar)
    }
    func appListScreen(_ title: String, isRoot: Bool = false) -> some View {
        listStyle(.insetGrouped)
            .appListBackground()
            .contentMargins(.horizontal, AppStyle.Layout.contentMargin, for: .scrollContent)
            .contentMargins(.bottom, AppStyle.Layout.contentMargin, for: .scrollContent)
            .listSectionSpacing(.custom(AppStyle.Spacing.large))
            .scrollDismissesKeyboard(.interactively)
            .appPageTitle(title, isRoot: isRoot)
    }
    func appFormScreen(_ title: String) -> some View {
        appListBackground()
            .contentMargins(.horizontal, AppStyle.Layout.contentMargin, for: .scrollContent)
            .contentMargins(.bottom, AppStyle.Layout.contentMargin, for: .scrollContent)
            .listSectionSpacing(.custom(AppStyle.Spacing.large))
            .scrollDismissesKeyboard(.interactively)
            .appPageTitle(title)
    }
    func appTabChrome() -> some View {
        toolbarBackground(AppStyle.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
    func appEditorSheet() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

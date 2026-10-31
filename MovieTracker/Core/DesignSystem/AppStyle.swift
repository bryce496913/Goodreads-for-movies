import SwiftUI

/// Semantic system colors adapt to light/dark mode and increased contrast.
/// Brand colors and custom typography are deliberately deferred.
enum AppStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }
}

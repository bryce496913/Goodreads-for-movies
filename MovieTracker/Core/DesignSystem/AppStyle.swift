import SwiftUI

/// Provisional visual identity. Named assets supply light/dark and increased-contrast variants.
enum AppStyle {
    enum Colors {
        static let canvas = Color("CanvasColor")
        static let surface = Color("SurfaceColor")
        static let raisedSurface = Color("RaisedSurfaceColor")
        static let primaryText = Color("PrimaryTextColor")
        static let secondaryText = Color("SecondaryTextColor")
        static let accent = Color("AccentColor")
        static let pressedAccent = Color("PressedAccentColor")
        static let onAccent = Color("OnAccentColor")
        static let divider = Color("DividerColor")
    }
    static let background = Colors.canvas
    static let surface = Colors.surface

    enum Typography {
        static let pageTitle = Font.largeTitle.weight(.bold)
        static let sectionHeading = Font.title2.weight(.semibold)
        static let mediaTitle = Font.headline
        static let metadata = Font.subheadline
        static let body = Font.body
        static let caption = Font.footnote
        static let smallLabel = Font.caption.weight(.semibold)
    }
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let compact: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }
    enum Radius {
        static let poster: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let artwork: CGFloat = 12
    }
    enum Layout {
        static let contentMargin = Spacing.medium
        static let minimumTarget: CGFloat = 44
        static let rowPosterWidth: CGFloat = 56
        static let rowPosterHeight: CGFloat = 84
    }
}

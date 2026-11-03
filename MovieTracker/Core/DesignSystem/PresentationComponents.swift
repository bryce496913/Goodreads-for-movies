import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    var systemImage: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.compact) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) }
                else { Text(title) }
            }
            .font(AppStyle.Typography.sectionHeading)
            .foregroundStyle(AppStyle.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(AppStyle.Typography.body)
                .foregroundStyle(AppStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Presentation only; callers retain either their network image or cache-only image implementation.
struct PosterFrame<Content: View>: View {
    private let content: Content
    private let width: CGFloat
    init(width: CGFloat = AppStyle.Layout.rowPosterWidth, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }
    var body: some View {
        content
            .frame(width: width, height: width * 1.5)
            .background(AppStyle.Colors.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.poster))
            .overlay { RoundedRectangle(cornerRadius: AppStyle.Radius.poster).strokeBorder(AppStyle.Colors.divider, lineWidth: 1) }
    }
}

struct ArtworkPlaceholder: View {
    var systemImage = "film"
    var body: some View {
        ZStack {
            Rectangle().fill(AppStyle.Colors.raisedSurface)
            Image(systemName: systemImage).font(.title3).foregroundStyle(AppStyle.Colors.secondaryText)
        }
    }
}

struct MediaTypeLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(AppStyle.Typography.smallLabel)
            .foregroundStyle(AppStyle.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xSmall)
            .background(AppStyle.Colors.raisedSurface, in: Capsule())
    }
}

struct AppLoadingState: View {
    let title: String
    var body: some View {
        ProgressView(title)
            .font(AppStyle.Typography.metadata)
            .foregroundStyle(AppStyle.Colors.secondaryText)
            .tint(AppStyle.Colors.accent)
            .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
    }
}

struct AppErrorMessage: View {
    let message: String
    var body: some View {
        Label {
            Text(message).font(AppStyle.Typography.body)
                .foregroundStyle(AppStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(AppStyle.Colors.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Non-destructive actions only. Native role-based destructive/editor controls remain native.
struct AppActionStyle: ButtonStyle {
    enum Emphasis { case primary, secondary }
    var emphasis: Emphasis = .secondary
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let foreground = !isEnabled ? AppStyle.Colors.secondaryText
            : emphasis == .primary ? AppStyle.Colors.onAccent : AppStyle.Colors.accent
        let background = !isEnabled ? AppStyle.Colors.raisedSurface
            : emphasis == .primary ? (configuration.isPressed ? AppStyle.Colors.pressedAccent : AppStyle.Colors.accent)
            : (configuration.isPressed ? AppStyle.Colors.raisedSurface : AppStyle.Colors.surface)
        return configuration.label
            .font(AppStyle.Typography.mediaTitle)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .frame(minWidth: AppStyle.Layout.minimumTarget, minHeight: AppStyle.Layout.minimumTarget)
            .background(background, in: RoundedRectangle(cornerRadius: AppStyle.Radius.control))
            .overlay { RoundedRectangle(cornerRadius: AppStyle.Radius.control).strokeBorder(emphasis == .secondary ? AppStyle.Colors.divider : .clear, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: AppStyle.Radius.control))
        // No scale/opacity animation: pressed and disabled states remain legible with Reduce Motion.
    }
}

extension View {
    /// Keep native List row chrome and scrolling; only the surrounding canvas is themed.
    func appListBackground() -> some View { scrollContentBackground(.hidden).background(AppStyle.background) }
}

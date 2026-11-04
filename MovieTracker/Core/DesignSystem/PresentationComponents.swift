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
    enum Emphasis { case primary, secondary, tertiary }
    var emphasis: Emphasis = .secondary
    var fillsWidth = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let foreground = !isEnabled ? AppStyle.Colors.secondaryText
            : emphasis == .primary ? AppStyle.Colors.onAccent : AppStyle.Colors.accent
        let background = !isEnabled ? AppStyle.Colors.raisedSurface
            : emphasis == .primary ? (configuration.isPressed ? AppStyle.Colors.pressedAccent : AppStyle.Colors.accent)
            : emphasis == .tertiary ? (configuration.isPressed ? AppStyle.Colors.raisedSurface : .clear)
            : (configuration.isPressed ? AppStyle.Colors.raisedSurface : AppStyle.Colors.surface)
        return configuration.label
            .font(AppStyle.Typography.mediaTitle)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppStyle.Spacing.medium)
            .padding(.vertical, AppStyle.Spacing.small)
            .frame(minWidth: AppStyle.Layout.minimumTarget, maxWidth: fillsWidth ? .infinity : nil, minHeight: AppStyle.Layout.minimumTarget)
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

// Destructive roles/confirmation dialogs keep system red and native pressed/disabled states.
extension View {
    func appDestructiveAction() -> some View {
        buttonStyle(.bordered).controlSize(.regular)
            .frame(minHeight: AppStyle.Layout.minimumTarget, alignment: .leading)
    }
}

struct FavoriteAction: View {
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(selected ? "Remove Favorite" : "Add Favorite", systemImage: selected ? "heart.fill" : "heart")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(AppActionStyle())
        .accessibilityLabel(selected ? "Remove Favorite" : "Add Favorite")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

struct ViewingStatusSelector: View {
    let status: LibraryStatus?
    let currentLabel: String
    let supportsWatching: Bool
    let canClear: Bool
    let change: (LibraryStatus?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text(currentLabel).font(AppStyle.Typography.metadata)
                .accessibilityIdentifier("library.currentStatus")
            Menu {
                option("Watchlist", value: .watchlist, identifier: "library.watchlistAction")
                if supportsWatching { option("Watching", value: .watching, identifier: "library.watchingAction") }
                option("Watched", value: .watched, identifier: "library.watchedAction")
                Divider()
                option("Clear viewing status", value: nil, identifier: "library.clearStatus")
                    .disabled(!canClear)
            } label: { Label("Viewing status", systemImage: "bookmark") }
            .buttonStyle(AppActionStyle(emphasis: .primary, fillsWidth: true))
            .accessibilityValue(currentLabel)
            .accessibilityIdentifier("library.statusSelector")
        }
    }
    private func option(_ label: String, value: LibraryStatus?, identifier: String) -> some View {
        Button { change(value) } label: {
            if (value == nil ? !canClear : status == value) { Label(label, systemImage: "checkmark") }
            else { Text(label) }
        }
        .accessibilityValue((value == nil ? !canClear : status == value) ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }
}

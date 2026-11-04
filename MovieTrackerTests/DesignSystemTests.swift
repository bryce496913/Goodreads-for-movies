import SwiftUI
import UIKit
import XCTest
@testable import MovieTracker

final class DesignSystemTests: XCTestCase {
    private let names = ["CanvasColor", "SurfaceColor", "RaisedSurfaceColor", "PrimaryTextColor", "SecondaryTextColor",
                         "AccentColor", "PressedAccentColor", "OnAccentColor", "DividerColor"]

    @MainActor func testAppShellDefinesExactlyFourUniqueNativeTabs() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Home", "Search", "Library", "Profile"])
        XCTAssertEqual(Set(AppTab.allCases.map(\.symbol)).count, 4)
        for tab in AppTab.allCases { XCTAssertNotNil(UIImage(systemName: tab.symbol)) }
    }

    @MainActor func testAllSemanticAssetsResolveForBothAppearancesAndContrastModes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                for name in names {
                    let color = try resolved(name, style: style, contrast: contrast)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
                    XCTAssertEqual(a, 1, accuracy: 0.001)
                }
            }
        }
    }

    @MainActor func testIntendedTextPairsMeetNormalTextContrast() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for mode in [UIAccessibilityContrast.normal, .high] {
                for foreground in ["PrimaryTextColor", "SecondaryTextColor", "AccentColor"] {
                    for background in ["CanvasColor", "SurfaceColor", "RaisedSurfaceColor"] {
                        let ratio = try contrast(resolved(foreground, style: style, contrast: mode), resolved(background, style: style, contrast: mode))
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(foreground) on \(background)")
                    }
                }
            }
        }
    }

    @MainActor func testPrimaryActionNormalPressedAndDisabledPairsRemainLegible() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for mode in [UIAccessibilityContrast.normal, .high] {
                for fill in ["AccentColor", "PressedAccentColor"] {
                    XCTAssertGreaterThanOrEqual(try contrast(resolved("OnAccentColor", style: style, contrast: mode), resolved(fill, style: style, contrast: mode)), 4.5)
                }
                XCTAssertGreaterThanOrEqual(try contrast(resolved("SecondaryTextColor", style: style, contrast: mode), resolved("RaisedSurfaceColor", style: style, contrast: mode)), 4.5)
            }
        }
    }

    @MainActor func testDarkCanvasAndIncreasedContrastAreAdaptive() throws {
        let light = try resolved("CanvasColor", style: .light), dark = try resolved("CanvasColor", style: .dark)
        XCTAssertGreaterThan(try luminance(light), try luminance(dark))
        for style in [UIUserInterfaceStyle.light, .dark] {
            let regular = try contrast(resolved("SecondaryTextColor", style: style), resolved("SurfaceColor", style: style))
            let increased = try contrast(resolved("SecondaryTextColor", style: style, contrast: .high), resolved("SurfaceColor", style: style, contrast: .high))
            XCTAssertGreaterThan(increased, regular)
        }
    }

    @MainActor func testSpacingGridAndArtworkHierarchy() {
        let steps = [AppStyle.Spacing.xSmall, AppStyle.Spacing.small, AppStyle.Spacing.compact,
                     AppStyle.Spacing.medium, AppStyle.Spacing.large, AppStyle.Spacing.xLarge]
        XCTAssertEqual(steps, [4, 8, 12, 16, 24, 32])
        XCTAssertTrue(steps.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
        XCTAssertLessThan(AppStyle.Radius.poster, AppStyle.Radius.card)
        XCTAssertGreaterThanOrEqual(AppStyle.Layout.minimumTarget, 44)
        XCTAssertEqual(AppStyle.Layout.rowPosterHeight / AppStyle.Layout.rowPosterWidth, 1.5)
    }

    @MainActor func testSharedComponentsFitCompactAndLargerWidthsInLightAndDark() {
        for scheme in [ColorScheme.light, .dark] {
            for width in [CGFloat(320), CGFloat(430)] {
                let size = measure(width: width, scheme: scheme, type: .large)
                XCTAssertGreaterThan(size.height, 0)
                XCTAssertTrue(size.height.isFinite)
                XCTAssertLessThanOrEqual(size.width, width + 0.5)
            }
        }
    }

    @MainActor func testLargestDynamicTypeExpandsLongContentVertically() {
        for scheme in [ColorScheme.light, .dark] {
            let regular = measure(width: 320, scheme: scheme, type: .large)
            let accessible = measure(width: 320, scheme: scheme, type: .accessibility5)
            XCTAssertGreaterThan(accessible.height, regular.height)
            XCTAssertLessThanOrEqual(accessible.width, 320.5)
        }
    }

    @MainActor func testTrackingComponentsFitCompactWidthAcrossProgressStates() throws {
        let summaries = [
            EpisodeProgressSummary(watched: 0, totalWatched: 0, eligible: 0, future: 0, unknownAirDate: 0, coverageKnown: false),
            EpisodeProgressSummary(watched: 0, totalWatched: 0, eligible: 8, future: 0, unknownAirDate: 0, coverageKnown: true),
            EpisodeProgressSummary(watched: 3, totalWatched: 4, eligible: 8, future: 1, unknownAirDate: 1, coverageKnown: true),
            EpisodeProgressSummary(watched: 8, totalWatched: 8, eligible: 8, future: 1, unknownAirDate: 0, coverageKnown: true),
            EpisodeProgressSummary(watched: 3, totalWatched: 3, eligible: 8, future: 0, unknownAirDate: 1, coverageKnown: false)
        ]
        let rating = try PersonalRating(halfStarUnits: 9)
        for summary in summaries {
            for type in [DynamicTypeSize.large, .accessibility5] {
                for scheme in [ColorScheme.light, .dark] {
                    let content = VStack(alignment: .leading) {
                        ProgressDescription(summary: summary, series: true)
                        PersonalRatingDisplay(rating: rating, label: "Your rating: 4.5 stars")
                    }.environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme)
                    let host = UIHostingController(rootView: content)
                    host.loadViewIfNeeded()
                    let size = host.sizeThatFits(in: CGSize(width: 288, height: 20_000))
                    XCTAssertGreaterThan(size.height, 0)
                    XCTAssertTrue(size.height.isFinite)
                    XCTAssertLessThanOrEqual(size.width, 288.5)
                }
            }
        }
    }

    @MainActor func testDashboardRowsWrapLongMetricsAndTitlesAtAccessibilitySizes() throws {
        let rating = try PersonalRating(halfStarUnits: 7)
        let title = DashboardTitle(id: MediaID(kind: .tvShow, value: "fixture:long"),
            title: String(repeating: "A long saved series title ", count: 5), year: nil, posterURL: nil, rating: rating)
        let store = LibraryStore(container: try PersistenceController.makeContainer(inMemory: true))
        for type in [DynamicTypeSize.large, .accessibility5] {
            for scheme in [ColorScheme.light, .dark] {
                let content = VStack(alignment: .leading) {
                    DashboardTitleRow(title: title)
                    DashboardMetricRow(label: "Series with watched episode progress", value: "1,000")
                    DashboardMetricRow(label: "Average personal rating", value: "Unavailable — no valid personal ratings")
                }.environment(store).environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme)
                let host = UIHostingController(rootView: content)
                host.loadViewIfNeeded()
                let size = host.sizeThatFits(in: CGSize(width: 288, height: 20_000))
                XCTAssertGreaterThan(size.height, 0)
                XCTAssertTrue(size.height.isFinite)
                XCTAssertLessThanOrEqual(size.width, 288.5)
            }
        }
    }

    @MainActor func testHomeActivityCopyPreservesValuesAndUnknownProgressCounts() throws {
        let title = DashboardTitle(id: MediaID(kind: .movie, value: "fixture:home"), title: "A saved movie",
            year: nil, posterURL: nil, rating: try PersonalRating(halfStarUnits: 5))
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let rated = DashboardActivity(id: "rating:fixture:home", title: title,
            label: "Personal rating updated: 2.5 stars", date: date, watchedDate: nil)
        XCTAssertEqual(HomePresentation.activityLabel(rated), "Rated 2.5 stars")
        let cleared = DashboardActivity(id: rated.id, title: title, label: "Personal rating cleared", date: date, watchedDate: nil)
        XCTAssertEqual(HomePresentation.activityLabel(cleared), "Rating cleared")
        XCTAssertEqual(HomePresentation.watchedCount(0), "0 episodes watched")
        XCTAssertEqual(HomePresentation.watchedCount(1), "1 episode watched")
        XCTAssertEqual(HomePresentation.watchedCount(3), "3 episodes watched")
    }

    @MainActor func testHomeOmitsOnlyActivityForViewingEventsAlreadyPreviewed() {
        let title = DashboardTitle(id: MediaID(kind: .movie, value: "fixture:home"), title: "A saved movie",
            year: nil, posterURL: nil, rating: nil)
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let event = DashboardDiaryItem(id: UUID(), title: title, watchedDate: date, recordedAt: date)
        let shown = DashboardActivity(id: "viewing:" + event.id.uuidString, title: title, label: "Viewing recorded", date: date, watchedDate: date)
        let undated = DashboardActivity(id: "viewing:undated", title: title, label: "Viewing recorded", date: date, watchedDate: nil)
        let rated = DashboardActivity(id: "rating:fixture:home", title: title, label: "Personal rating cleared", date: date, watchedDate: nil)
        let snapshot = DashboardSnapshot(statistics: ViewingStatistics(watchedMovies: 1, seriesWithProgress: 0,
            watchedEpisodes: 0, watchlist: 0, favorites: 0, ratings: 0, averageRating: nil, reviews: 0, viewingEvents: 2),
            continueWatching: [], recentlyWatched: [event], recentDiary: [event], watchlist: [], activity: [shown, undated, rated],
            duplicateTitles: 0, invalidRatings: 0, unclassifiedTitles: 0, hasPersonalData: true)
        XCTAssertEqual(HomePresentation.activity(in: snapshot).map(\.id), [undated.id, rated.id])
        XCTAssertEqual(snapshot.activity.count, 3)
        XCTAssertEqual(snapshot.recentlyWatched.count, 1)
    }

    @MainActor private func resolved(_ name: String, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast = .normal) throws -> UIColor {
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
        return try XCTUnwrap(UIColor(named: name, in: .main, compatibleWith: traits)).resolvedColor(with: traits)
    }
    @MainActor private func luminance(_ color: UIColor) throws -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { throw DesignTestError.unresolvedColor }
        func linear(_ value: CGFloat) -> Double {
            let c = Double(value); return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
    }
    @MainActor private func contrast(_ first: UIColor, _ second: UIColor) throws -> Double {
        let a = try luminance(first), b = try luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    @MainActor private func measure(width: CGFloat, scheme: ColorScheme, type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: components.environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme))
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.loadViewIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: 20_000))
    }
    @MainActor private var components: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
            PageHeader(title: "A long editorial title that wraps across several lines", subtitle: "Supporting text stays readable as text grows.")
            SectionHeading(title: "Saved stories")
            HStack(alignment: .top, spacing: AppStyle.Spacing.medium) {
                PosterFrame { ArtworkPlaceholder() }
                VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    Text("A long movie or series title for layout validation").font(AppStyle.Typography.mediaTitle).fixedSize(horizontal: false, vertical: true)
                    MediaTypeLabel(title: "TV Show")
                }
            }
            EmptyStateCard(title: "No saved stories yet", systemImage: "books.vertical", message: "Find a movie or series and save it from Details.")
            AppErrorMessage(message: "A metadata request failed. Saved personal records remain available.")
            AppLoadingState(title: "Loading details…")
            RatingStars(rating: try? PersonalRating(halfStarUnits: 7))
            Button("Find Movies and TV") {}.buttonStyle(AppActionStyle(emphasis: .primary))
            Button("Retry Details") {}.buttonStyle(AppActionStyle())
            Button("Disabled action") {}.buttonStyle(AppActionStyle(emphasis: .primary)).disabled(true)
        }
        .padding(AppStyle.Layout.contentMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppStyle.background)
    }
}
private enum DesignTestError: Error { case unresolvedColor }

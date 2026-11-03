# Search and media detail presentation (021)

## Inspection and changes

Search retains the native searchable navigation drawer, segmented media filter (menu at accessibility sizes), native list, explicit pagination/retry actions and all existing empty/error states. Compact rows suit mixed titles and long text better than a grid. Search posters increase from 56 × 84 to 72 × 108; the shared PosterFrame keeps its original default for other screens. Title is followed by one wrapping movie/TV and year line instead of competing badge and year rows. The combined accessible row label retains title, type and year.

Details retain the native Details navigation title and typed destination. Available backdrops use 16:9, posters 2:3, rounded corners and existing bounded image requests. Missing backdrops omit the empty hero; missing posters retain a labeled placeholder. Title and text remain outside artwork for contrast. Existing accessibility layout stacks poster and title vertically.

Movie/series facts and genres precede personal actions. Viewing status and favorites remain visible in a two-column action group, changing to one column from XXXL Dynamic Type onward. Filled SF Symbols and accessible Selected/Not selected values reflect persisted state. Personal rating follows viewing actions and keeps its existing accessible editor. Destructive removal retains its native role and confirmation.

TV episode progress and seasons precede synopsis and cast. Movies proceed directly to synopsis and cast. Reviews and viewing history follow these sections; metadata freshness, errors, attribution and explicit refresh remain available. No extra view task, automatic refresh, image transport, cache or navigation route was added. Cast remains text-only because the existing cast model supplies names and roles, not photos; no invented portraits or additional provider requests.

## Behavior boundaries

SearchModel, MediaDetailModel, episode progress, persistence, domain entities, metadata services, cache retention, query normalization, filters, cancellation, pagination and rating logic are unchanged. Existing action closures still invoke the same centralized library operations. Status changes, favorites and ratings remain independent. Artwork continues to use the provider-approved existing memory-only infrastructure; no disk cache is introduced.

## Validation

Linux static checks passed: OpenStep project parsing, complete source membership in all three targets, file-reference resolution, Swift grammar parsing (135 files), asset JSON parsing and 44 intended text contrast pairs across four appearances. `git diff --check` passed. These checks do not compile or type-check Swift.

All 357 XCTest methods are **UNRUN** here: Xcode, Apple SDKs and simulators are unavailable. No compilation, device-build check or GitHub Xcode CI was added. No before/after runtime screenshots are available. Existing UI tests attach Search/movie/TV/missing-artwork/large-text screenshots when run locally.

Updated mocked regressions assert movie/TV identity and year, missing-backdrop omission and poster fallback. An added UI regression checks that watching/watched selection and favorite selection remain independent. Existing rating, search/filter/pagination/back-navigation, missing metadata, long-title dark accessibility, diary and episode tests remain in place.

## Local review

Run the existing MovieTrackerTests and MovieTrackerUITests targets in Xcode using an available simulator. In particular run SearchTests, MediaDetailUITests, RatingUITests and the existing library/diary/TV progress suites (select their actual classes in the test navigator). Use the `--ui-testing-search` fixture launch mode; existing detail modes include `missing` and `long`.

Inspect compact and larger iPhones, light/dark and increased contrast, largest accessibility text, VoiceOver and Reduce Motion. Check row wrapping, all filter selections, pagination then back navigation, poster fallback, metadata before actions, selected states, independent rating/status/favorite mutations, TV seasons, private review editors and destructive confirmation. Capture fixture screenshots for comparison. Rendering, touch-target reachability and runtime state preservation remain unverified until these local runs pass.

# Buttons, controls and personal actions (026)

## Control inventory

| Context | Standardized treatment |
| --- | --- |
| Primary actions | AppActionStyle primary, adaptive accent fill/on-accent text, optional full-width layout. Used for viewing status, empty Home/Library Search actions, failed Search retry, credential save and personal export. |
| Secondary actions | AppActionStyle secondary, subtle surface/divider, same radius/44-point minimum-height family. Used for rating editing, supporting diary/review actions and restore. |
| Tertiary actions | AppActionStyle tertiary, no resting fill/border; retains visible pressed/disabled feedback and 44-point minimum target. Used for detail refresh and Search Load More. |
| Destructive actions | Shared appDestructiveAction helper keeps native bordered styling, destructive role and system pressed/disabled colors. Library removal, review/event deletion and credential removal retain existing confirmation. Native alert/menu confirmations remain native. |
| Viewing status | One ViewingStatusSelector menu, current persisted text, check-marked selection and accessible current value. TV supports Watchlist/Watching/Watched/clear; movies omit Watching. |
| Favorite | Independent FavoriteAction heart button, outline/filled state, explicit Add/Remove Favorite label and Selected/Not selected value. No status/rating coupling. |
| Personal rating | Stars and explicit value are read-only. One native edit menu offers all ten half-star values, Unrated and explicit Clear Personal Rating. No competing stepper or precise star taps. |
| Native navigation/editors | Back/swipe-back, native tabs, Save/Cancel/Done toolbars, segmented filters, episode toggles and menus retain native behavior. No custom circular back control was found or introduced. |

AppActionStyle adds only a tertiary emphasis and optional width policy to the existing style. Typography, horizontal padding, radius, target minimum, pressed/disabled colors and wrapping remain shared. Buttons grow vertically for long labels/large text instead of imposing a fixed height. FavoriteAction and ViewingStatusSelector are small reusable presentation components; they do not own persistence. No new control framework or toast system was added.

## Personal action behavior

The detail screen now presents current status plus one filled status-menu action, a separate compact heart, one rating editor, then removal below routine controls. The menu sets one exclusive viewing status; selecting an existing status is idempotent. Choosing Clear viewing status changes only that property. Inactive clear is disabled, while an unrecognized persisted raw status remains manually clearable. Remove from Library retains its original warning about which fields are removed and which reviews/history/progress survive.

Status writes still call LibraryStore.setStatus; favorite writes still call setFavorite. PersonalRatingControl retains the original units binding: validated integer 1...10, nil for unrated, original save closure, error alert and Saved feedback only after save succeeds. Unrated is disabled when already unrated to avoid creating an empty personal record through a redundant clear. An invalid stored value remains visibly unavailable and replaceable/clearable. Rating and status clearing are not styled as whole-record deletion.

No optimistic status/favorite state was added: values derive from the persisted entry and the store retains its existing save/rollback path. Rating save failure still clears Saved and presents its existing error. Other existing native success/error feedback remains. No haptic, animation or duplicate banner system was introduced; system menus/controls remain subject to native accessibility behavior.

## Audit and safe areas

Reviewed Home, Search, Library, Profile, movie/TV detail, TV tracking, ratings, reviews, diary, Settings, backup and editor control paths. Routine review/diary buttons now share the action family. Whole-record deletions and credential removal retain native destructive roles. Season bulk actions retain the existing secondary menu and confirmation. Search/filter/sort algorithms, route definitions and editor Save/Cancel handlers are untouched.

Shared appListScreen/appFormScreen now apply the existing 16-point bottom scroll-content margin; Home removes its duplicate local margin. MediaDetailView uses the same token as native bottom safe-area padding. Automatic tab/keyboard insets remain authoritative, with no tab-height estimate, custom bar, ignoresSafeArea or device-specific offset. Existing editor keyboard Done controls remain.

Source inspection cannot reproduce the reported screenshot overlap without a running device. These changes and geometry assertions are not runtime proof that every overlap is fixed. All menus, sheets, native file pickers and keyboard transitions still require local inspection.

## Data boundaries

No domain entity, SwiftData schema, migration, LibraryStore, metadata/cache service, search/progress model, dashboard aggregator or Library projection changed. Existing status/rating/favorite transactions and independent fields remain. Menus replace competing input affordances, not the underlying data model. Review/event deletion and credential removal confirmation handlers remain unchanged.

## Tests and evidence

Four new methods cover:

- All TV status-to-status transitions (including none) while preserving an independent favorite and 2.5-star rating, with one Library record.
- Movie selector excludes Watching; largest-text dark removal control fits above the tab bar, and cancellation preserves the entry.
- Every half-star value through the single accessible editor, followed by clearing.
- Compact-width primary/secondary/tertiary/destructive/favorite/status/rating layout in normal/largest text and light/dark.

Updated existing Library/filter/detail/rating tests to open the appropriate menu before choosing status/clear. The former stepper test now exercises the 0.5-star menu option and status independence. Existing removal, review deletion, episode watched actions, protected editor/navigation, persistent relaunch and safe-area suites remain.

Linux checks pass: project parsing and referenced files/source membership in all three targets; Swift grammar for 135 files; asset JSON; all 44 intended text contrast pairs across nine adaptive assets; whitespace; relative links; protected model/persistence/network/aggregation files. Grammar parsing is not Swift compilation or type checking. Native destructive system colors are not certified by the asset-only contrast script.

All **377 XCTest methods are UNRUN**: Linux has no Xcode, Apple SDKs or simulator. No Xcode build/device checks or GitHub Xcode CI added. No runtime before/after screenshots are available. Existing rating screenshots and a new largest-text dark personal-controls attachment are captured when the deterministic UI suites run locally.

## Local validation / deferred issues

Run LibraryUITests, RatingUITests, MediaDetailUITests, LibraryOrganizationUITests, DiaryUITests, TVProgressUITests, AppShellUITests and DesignSystemTests, followed by the existing full regression targets. Validate native menu element mapping/selected values, all status transitions and nil, independent favorites/ratings, invalid stored values, save-failure rollback, deletion cancel/confirm and persistent relaunch. Inspect light/dark/high contrast, compact/large iPhones, largest text, VoiceOver/Switch Control and Reduce Motion.

Check every final action's full frame above the tab bar, keyboard-safe editor Save/Cancel/Done, filter menus and file-provider sheets. Capture before/after detail/action screenshots and representative states locally. Runtime wrapping, menu accessibility, system destructive contrast, native sheet safe areas and actual persistence failures remain unverified. If overlap persists, inspect real safe-area frames before adding further spacing; no speculative device-specific workaround is included.

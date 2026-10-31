# Foundation validation — pass 002

## Recorded environment and results

Validation started from merged PR #001 (`5cdcf4998b1b7ed7978e7816daea53fe8d256a76`). The execution host is Linux. No Swift compiler, Xcode, Apple SDK, or iOS simulator is installed.

| Check | Recorded result |
| --- | --- |
| `xcodebuild -version` | Exit 127: `xcodebuild: command not found` |
| `xcrun simctl list devices available` | Exit 127: `xcrun: command not found` |
| Verified Xcode version / simulator destinations | None available |
| iOS build / unit tests / UI tests | Not run; no successful build or test command recorded |
| Project syntax, references, file existence, target source membership | Passed for app, unit tests, and UI tests |
| Shared scheme XML / test references | Passed; both test bundles enabled |
| Swift source grammar | Passed for all 18 source/test files; not type checking or macro expansion |
| Asset catalog JSON | Passed; no named images referenced and no final app icon configured |
| Whitespace validation | `git diff --check` passed |

Static checks used the npm `xcode` 4.0.0 project parser, `tree-sitter` 0.22.4 with `tree-sitter-swift` 0.7.1, and Python XML/JSON/assertion checks outside the checkout. These are validation-only tools, not app dependencies. Project checks resolved object references and compared each target's source phase with files on disk. They also checked one app entry point, four navigation stacks, both enabled test bundles, Swift 6, iOS 17, automatic signing, unit-test host/loader, UI-test target, and Debug testability. No missing referenced files were found. There is no GitHub Xcode CI workflow.

**Runtime acceptance remains unverified:** compilation, launch, SwiftData initialization/reopening/failure behavior, unit/UI test results, offline launch, layouts, accessibility, backgrounding, and navigation must still be tested on macOS. Source inspection or a syntax parser cannot establish those outcomes. No actual compiler defect was confirmed on this host, and functioning project settings were not rewritten speculatively.

## Repairs and coverage

- Library cards combine their text into one accessibility element. The old UI test queried an exact child title; the test now queries a stable card identifier without splitting VoiceOver's combined label.
- Settings has a stable identifier. Navigation tests scroll to it and assert reachability rather than assuming it fits on the initial screen. Navigation assertions wait for the expected bar and check that only one bar is present.
- Added startup/background/foreground/cold-relaunch coverage and a largest-accessibility-text Settings reachability test.
- Added a container initializer accepting an explicit local store URL for disk tests. Production still uses the original persistent default store with CloudKit disabled; in-memory tests retain their separate configuration.
- Added tests for a fresh isolated disk store, save/reopen fidelity, and throwing on an unusable path without overwriting its blocking file. Tests clean up only their own UUID-named temporary directory, never the application's default store.
- Existing movie/TV identity, metadata, empty-memory-store, conversion, and isolation tests remain. Total: **13 test methods included, zero executed on this host** (4 domain, 6 persistence, 3 UI).

The storage model uses supported scalar/optional attributes and a UUID uniqueness constraint, with no relationships. App startup catches container errors and presents retry UI rather than deleting data or substituting an empty in-memory store. There is no seed insertion or networking in app sources. These are code-inspection findings, pending Apple-platform runtime confirmation.

## Local build and test commands — not executed here

Use the latest stable Xcode supporting Swift 6 and an installed iPhone simulator running iOS 17 or newer. Record the actual Xcode version and destination UUIDs in the review results. Automatic signing is configured; simulator checks disable signing. Device builds can supply `DEVELOPMENT_TEAM=<YOUR_TEAM_ID>` or select a team in Xcode. Keep signing credentials and provisioning files out of Git. Bundle IDs are syntactically valid placeholders, not distribution identifiers.

From the repository root, in Bash:

```bash
set -euo pipefail
xcodebuild -version
xcodebuild -list -project MovieTracker.xcodeproj
xcrun simctl list devices available

# Replace the placeholder with one UUID from the list above.
SIMULATOR_ID='<SIMULATOR_UUID>'
# Each run gets fresh output locations; no previous results or user data are removed.
VALIDATION_DIR="$(mktemp -d /tmp/MovieTracker-validation.XXXXXX)"

xcodebuild build \
  -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$VALIDATION_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$VALIDATION_DIR/build.log"

xcodebuild test \
  -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$VALIDATION_DIR/DerivedData" \
  -resultBundlePath "$VALIDATION_DIR/Tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$VALIDATION_DIR/test.log"
```

`pipefail` preserves failures rather than reporting `tee`'s success. Confirm all 13 tests actually execute in the result bundle and record skipped/failed tests separately. Repeat on a compact supported iPhone (for example SE 3rd generation if available) and a current larger-screen iPhone. Use available actual destinations rather than treating these examples as recorded runs. Do not commit logs, DerivedData, or result bundles.

## Manual simulator/device matrix — all pending

Use a dedicated simulator for a clean-install check; do not erase an existing user device or delete its store. Inspect screenshots and VoiceOver reading order; UI test success alone cannot prove there is no clipping or overlap.

| Scenario on both compact and larger iPhone | Expected behavior |
| --- | --- |
| Fresh install and cold launch | Welcome and four tabs load; no error, fake library entries, account, or network requirement |
| All tabs and Profile → Settings → Back | One navigation bar; reachable controls; expected titles; Settings stack preserved after switching to Home and back |
| Light and dark appearance | System surfaces, primary/secondary labels, cards, search and Settings remain readable |
| Large Dynamic Type and largest accessibility category | Scrollable content, readable multiline text, reachable Settings and tab controls; no overlapping labels/buttons |
| VoiceOver / increased contrast | Meaningful tab/control labels, combined card text, section headings and visible contrast |
| Disable networking, terminate, relaunch | Local container and all placeholder screens still load |
| Background and reopen, then terminate/relaunch | No crash; active navigation survives backgrounding; cold launch opens Home and the persistent store |
| Rotate device | Portrait remains the supported orientation; UI does not become blank or inaccessible |
| Persistence failure | Visible retry UI, no destructive reset or silent in-memory replacement; unit test separately verifies initializer throws |

No metadata integration or new product feature is included in this pass.

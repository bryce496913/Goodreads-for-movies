#!/bin/bash
# Local macOS validation only; never uploads, signs an archive, deletes data, or runs in GitHub CI.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null || ! command -v xcrun >/dev/null; then
    echo 'UNVERIFIED: macOS, Xcode and an installed iOS simulator are required.' >&2
    exit 69
fi
if [[ $# -ne 1 ]]; then
    echo 'Usage: scripts/validate-v05.sh <installed-simulator-UUID>' >&2
    exit 64
fi
cd "$(dirname "$0")/.."
validation_dir="$(mktemp -d /tmp/MovieTracker-v05.XXXXXX)"
echo "Validation output: $validation_dir"
xcodebuild -version | tee "$validation_dir/xcode-version.log"
xcrun simctl list devices available > "$validation_dir/destinations.log"
destination="platform=iOS Simulator,id=$1"
# Remove the optional live development token from these credential-free deterministic runs.
for configuration in Debug Release; do
    env -u TMDB_READ_ACCESS_TOKEN xcodebuild build -project MovieTracker.xcodeproj -scheme MovieTracker \
        -configuration "$configuration" -destination "$destination" \
        -derivedDataPath "$validation_dir/DerivedData" CODE_SIGNING_ALLOWED=NO \
        2>&1 | tee "$validation_dir/build-$configuration.log"
done
env -u TMDB_READ_ACCESS_TOKEN xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
    -configuration Debug -destination "$destination" \
    -derivedDataPath "$validation_dir/DerivedData" -resultBundlePath "$validation_dir/Tests.xcresult" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$validation_dir/test.log"
echo 'Build and XCTest commands succeeded. Manual, migration, signing and archive gates still need review.'

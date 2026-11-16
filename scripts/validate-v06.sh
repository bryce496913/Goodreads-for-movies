#!/bin/bash
# Owner-run Apple validation. Never uploads, signs a device build, deletes stores, or runs in GitHub CI.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null || ! command -v xcrun >/dev/null; then
    echo 'UNVERIFIED: macOS, Xcode and an installed iOS simulator are required.' >&2
    exit 69
fi
if [[ $# -ne 1 ]]; then
    echo 'Usage: scripts/validate-v06.sh <installed-test-simulator-UUID>' >&2
    exit 64
fi
cd "$(dirname "$0")/.."
validation_dir="$(mktemp -d /tmp/MovieTracker-v06.XXXXXX)"
echo "Validation output: $validation_dir"
xcodebuild -version | tee "$validation_dir/xcode-version.log"
xcrun simctl list devices available > "$validation_dir/destinations.log"
env -u TMDB_READ_ACCESS_TOKEN xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
    -configuration Debug -destination "platform=iOS Simulator,id=$1" \
    -parallel-testing-enabled NO -derivedDataPath "$validation_dir/DerivedData" \
    -resultBundlePath "$validation_dir/Tests.xcresult" CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "$validation_dir/test.log"
echo 'XCTest command succeeded. Review its xcresult for skips/failures; real historical stores, manual accessibility and provider-rights gates remain separate. TestFlight is deferred.'

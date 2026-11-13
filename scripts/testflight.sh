#!/usr/bin/env bash
# Archive a Release build and upload it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh            # archive and upload
#   scripts/testflight.sh --archive  # archive only (check signing without uploading)
#
# Needs: Xcode signed in to the Apple ID on team 2779EQ3QB6 (Xcode → Settings → Accounts),
# and the app created in App Store Connect with bundle ID com.ctsmith5.hours.
# The build number is the git commit count, so commit before each upload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -z "$(git status --porcelain -- Hours Config Hours.xcodeproj)" ]] \
  || { echo "error: commit your changes first; the build number comes from the commit count" >&2; exit 1; }

BUILD="$(git rev-list --count HEAD)"
ARCHIVE="build/Hours-$BUILD.xcarchive"
echo "==> Archiving build $BUILD"
xcodebuild archive -quiet \
  -project Hours.xcodeproj -scheme Hours -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD"

[[ "${1:-}" == "--archive" ]] && { echo "Archived $ARCHIVE"; exit 0; }

echo "==> Uploading build $BUILD to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "build/export-$BUILD" -allowProvisioningUpdates

echo "Uploaded build $BUILD. It shows up in App Store Connect → TestFlight after processing (usually 5–15 minutes)."

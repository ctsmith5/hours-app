#!/usr/bin/env bash
# Archive a build and upload it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh                      # production build (Release), archive and upload
#   scripts/testflight.sh --staging            # staging build: talks to the staging API, shows a STAGING band
#   scripts/testflight.sh [--staging] --archive  # archive only (check signing without uploading)
#
# Needs: Xcode signed in to the Apple ID on team 2779EQ3QB6 (Xcode → Settings → Accounts),
# and the app created in App Store Connect with bundle ID com.ctsmith5.hours.
#
# Both kinds of build go to the same app, so build numbers can't collide: the build number is
# the git commit count × 10, plus 1 for staging (commit 6 → production 60, staging 61).
# In TestFlight, staging builds are the odd ones and show as "Hours Staging" on the phone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION=Release
OFFSET=0
ARCHIVE_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --staging) CONFIGURATION=Staging; OFFSET=1 ;;
    --archive) ARCHIVE_ONLY=true ;;
    *) echo "usage: scripts/testflight.sh [--staging] [--archive]" >&2; exit 2 ;;
  esac
done

[[ -z "$(git status --porcelain -- Hours Config Hours.xcodeproj)" ]] \
  || { echo "error: commit your changes first; the build number comes from the commit count" >&2; exit 1; }

BUILD=$(( $(git rev-list --count HEAD) * 10 + OFFSET ))
ARCHIVE="build/Hours-$CONFIGURATION-$BUILD.xcarchive"
echo "==> Archiving $CONFIGURATION build $BUILD"
xcodebuild archive -quiet \
  -project Hours.xcodeproj -scheme Hours -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD"

$ARCHIVE_ONLY && { echo "Archived $ARCHIVE"; exit 0; }

echo "==> Uploading $CONFIGURATION build $BUILD to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "build/export-$CONFIGURATION-$BUILD" -allowProvisioningUpdates

echo "Uploaded $CONFIGURATION build $BUILD. It shows up in App Store Connect → TestFlight after processing (usually 5–15 minutes)."

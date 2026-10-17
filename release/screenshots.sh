#!/bin/bash
# Rebuild the README and website images: builds a throwaway copy of Beckon,
# runs its screenshot mode (made-up devices; nothing rings, real settings are
# never touched), then composes the screenshots, widgets picture and demo
# GIF/MP4 into docs/.
#
#   release/screenshots.sh
#
# The copy has its widget and Siri metadata removed, so macOS never mistakes
# it for the installed app. Its windows sit behind your other windows while
# it runs (about 25 seconds).
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cleanup() {
  # xcodebuild and launching both register the copies with LaunchServices;
  # take them back out so only /Applications/Beckon.app stays known.
  for app in "$WORK/BeckonShots.app" "$WORK/dd/Build/Products/Debug/Beckon.app"; do
    "$LSREG" -u "$app" 2>/dev/null || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

.tools/xcodegen/bin/xcodegen generate --spec project.yml --quiet
xcodebuild -project FindMyRing.xcodeproj -scheme FindMyRing -configuration Debug \
  -derivedDataPath "$WORK/dd" CODE_SIGNING_ALLOWED=NO build -quiet
APP="$WORK/BeckonShots.app"
ditto "$WORK/dd/Build/Products/Debug/Beckon.app" "$APP"
"$LSREG" -u "$WORK/dd/Build/Products/Debug/Beckon.app" 2>/dev/null || true
rm -rf "$WORK/dd" "$APP/Contents/PlugIns" "$APP/Contents/Resources/Metadata.appintents"

"$APP/Contents/MacOS/Beckon" --screenshots "$WORK/raw"
python3 release/make_media.py "$WORK/raw" docs

#!/bin/bash
# Build Beckon signed with Developer ID, notarized by Apple, and stapled —
# the form in which macOS will load the third-party widget and others can run it.
# Signing + notarization go through Xcode's signed-in account; no cert or
# password is handled here.
#
#   TEAM_ID=4JWVY7832S release/notarize.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
TEAM_ID="${TEAM_ID:-4JWVY7832S}"
BUILD="release/build/$VERSION"
ARCHIVE="$BUILD/FindMyRing.xcarchive"

if [[ -e "$BUILD" ]]; then
  echo "Build folder already exists: $BUILD. Use a new version or move it aside." >&2
  exit 1
fi
mkdir -p "$BUILD"

.tools/xcodegen/bin/xcodegen generate --spec project.yml --quiet

echo "[1/4] Archiving…"
xcodebuild -project FindMyRing.xcodeproj -scheme FindMyRing -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$BUILD/dd" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" archive -quiet

cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST

echo "[2/4] Exporting + uploading to the notary service…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -exportPath "$BUILD/export" -allowProvisioningUpdates -quiet

echo "[3/4] Waiting for Apple to notarize…"
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$BUILD/notarized" >/dev/null 2>&1; do
  sleep 20
done

APP="$BUILD/notarized/Beckon.app"
echo "[4/4] Notarized. Gatekeeper check:"
spctl -a -vv -t exec "$APP"
ditto -c -k --keepParent "$APP" "$BUILD/Beckon.zip"
echo "DONE: $APP"
echo "ZIP:  $BUILD/Beckon.zip"

# Finder installer for first-time users; ZIP remains the Sparkle update payload.
bash release/make-dmg.sh "$APP" "$BUILD/Beckon.dmg"

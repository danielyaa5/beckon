#!/bin/bash
# Run after notarization. Publishes nothing; review the feed before uploading.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage: make-appcast.sh VERSION}"
BUILD="release/build/$VERSION"
TOOL=".tools/sparkle/bin/generate_appcast"
if [[ ! -x "$TOOL" ]]; then
  echo 'Install the Sparkle 2.10.0 release tools in .tools/sparkle first.' >&2
  exit 1
fi
mkdir -p "$BUILD/feed"
ditto "$BUILD/Beckon.zip" "$BUILD/feed/Beckon.zip"
"$TOOL" --account beckon --maximum-deltas 0 \
  --download-url-prefix "https://github.com/danielyaa5/beckon/releases/download/v$VERSION/" \
  "$BUILD/feed"
echo "Review $BUILD/feed/appcast.xml; copy to docs/appcast.xml when publishing the matching GitHub release."

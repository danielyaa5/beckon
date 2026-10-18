#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(cd "$1" && pwd)"
OUTPUT="$2"
PYTHON=".tools/dmgbuild/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  python3 -m venv .tools/dmgbuild
  .tools/dmgbuild/bin/pip install 'dmgbuild==1.6.7' Pillow
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"$PYTHON" - "$WORK" "$APP" <<'PY'
import sys, plistlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
work, app = map(Path, sys.argv[1:])
im = Image.new('RGB', (1280, 840), '#f5f5f7')
d = ImageDraw.Draw(im)
font = '/System/Library/Fonts/Helvetica.ttc'
def text(y, value, size, fill):
    d.text((640, y), value, font=ImageFont.truetype(font, size), fill=fill, anchor='mm')
text(88, 'Drag Beckon into Applications', 42, '#202024')
d.line((590, 365, 685, 365), fill='#f07830', width=9)
d.polygon(((685, 365), (655, 340), (655, 390)), fill='#f07830')
text(575, 'Then open Beckon from Applications.', 30, '#404048')
text(625, 'Open Beckon to eject and remove this installer.', 25, '#666670')
im.save(work / 'background.png', dpi=(144,144))
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
(work / '.beckon-installer').write_text(info['CFBundleVersion'])
PY
.tools/dmgbuild/bin/dmgbuild -s release/dmg-settings.py \
  -D app="$APP" -D marker="$WORK/.beckon-installer" -D background="$WORK/background.png" \
  'Beckon Installer' "$OUTPUT"
echo "DMG: $OUTPUT"

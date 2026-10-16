#!/bin/zsh
# make-icon.swift로 아이콘을 다시 그려 앱·확장·README 자리에 넣는다.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift Icon/make-icon.swift "$TMP"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
for n in 16 32 48 128; do cp "$TMP/extension-$n.png" "Extension/icons/icon-$n.png"; done
sips -z 256 256 "$TMP/icon-1024.png" --out docs/icon.png >/dev/null
rm -rf "$TMP"
echo "icons updated"

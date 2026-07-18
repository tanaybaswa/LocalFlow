#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MASTER="$ROOT/Resources/icon-source/master-1024.png"
ICONSET="$ROOT/Resources/AppIcon.iconset"
if [[ ! -f "$MASTER" ]]; then
  echo "Missing $MASTER — generate icon master first." >&2
  exit 1
fi
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote Resources/AppIcon.icns"

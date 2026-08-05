#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCE="$ROOT/Design/AppIcon/colerm-logo-reference.png"
SOURCE="$ROOT/Design/AppIcon/colerm-logo-source.png"
ICONSET="$ROOT/Resources/AppIcon.appiconset"
LOGO_OUTPUT="$ROOT/Design/AppIcon/colerm-logo-1024.png"
FULL_BLEED_COLOR="#E95A3C"

if [[ ! -f "$REFERENCE" ]]; then
  echo "Icon reference not found." >&2
  exit 1
fi
if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick magick is required." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/colerm-app-icon.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# The reference is a presentation screenshot: remove its connected lavender
# surround, trim to the red logo, then flatten the transparent rounded corners
# onto the logo's coral fill so the source is full-bleed.
EXTRACTED="$WORK_DIR/extracted.png"
magick "$REFERENCE" \
  -alpha on \
  -fuzz 12% \
  -fill none \
  -draw 'color 0,0 floodfill' \
  -trim +repage \
  "$EXTRACTED"
SIZE="$(magick "$EXTRACTED" -format '%wx%h' info:)"
magick -size "$SIZE" "xc:$FULL_BLEED_COLOR" "$EXTRACTED" \
  -compose over -composite \
  -strip "$SOURCE"

ICON_BASE="$WORK_DIR/macos-icon-inner-base.png"
ICON_MASK="$WORK_DIR/macos-icon-inner-mask.png"
ICON_INNER="$WORK_DIR/macos-icon-inner.png"
ICON_MASTER="$WORK_DIR/macos-icon-master.png"

magick "$SOURCE" \
  -auto-orient \
  -resize "824x824^" \
  -gravity center \
  -extent 824x824 \
  -colorspace sRGB \
  -strip \
  "$ICON_BASE"
magick -size 824x824 xc:none \
  -fill white \
  -draw "path 'M 181 0 H 643 C 733 0 824 91 824 181 V 643 C 824 733 733 824 643 824 H 181 C 91 824 0 733 0 643 V 181 C 0 91 91 0 181 0 Z'" \
  "$ICON_MASK"
magick "$ICON_BASE" "$ICON_MASK" \
  -compose CopyOpacity \
  -composite \
  -strip \
  "$ICON_INNER"
magick -size 1024x1024 xc:none "$ICON_INNER" \
  -geometry +100+100 \
  -compose over \
  -composite \
  "$ICON_MASTER"
cp "$ICON_MASTER" "$LOGO_OUTPUT"

ICON_FILES=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)
for icon in "${ICON_FILES[@]}"; do
  IFS=: read -r filename size <<< "$icon"
  magick "$ICON_MASTER" -resize "${size}x${size}" "$ICONSET/$filename"
done

TEMP_ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/colerm-iconset.XXXXXX")/Colerm.iconset"
trap 'rm -rf "$WORK_DIR" "${TEMP_ICONSET%/*}"' EXIT
mkdir -p "$TEMP_ICONSET"
cp "$ICONSET"/*.png "$TEMP_ICONSET/"
iconutil -c icns -o "$ROOT/Resources/Colerm.icns" "$TEMP_ICONSET"

  echo "App icon prepared."

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""
OUT_DIR="$ROOT/dist"
DMG_NAME="Colerm.dmg"

usage() {
  cat <<EOF
Usage: $(basename "$0") --app <path> [options]

Options:
  --app <path>          App bundle to package
  --out <directory>     Output directory (default: dist)
  --name <filename>     DMG filename (default: Colerm.dmg)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2 ;;
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    --name) DMG_NAME="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$APP" || ! -d "$APP" ]]; then
  usage >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

APP_NAME="$(basename "$APP" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT_DIR/$DMG_NAME"
rm -f "$DMG"

STAGING_DIR="$(mktemp -d "${TMPDIR%/}/colerm-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG" >/dev/null
echo "DMG ready: $DMG"

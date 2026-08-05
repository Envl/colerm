#!/usr/bin/env bash
set -euo pipefail

APP=""
DMG=""
NOTARY_PROFILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") (--app <path> | --dmg <path>) --notary-profile <name>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?}"; shift 2 ;;
    --dmg) DMG="${2:?}"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$APP" && -n "$DMG" ]] ||
   [[ -z "$APP" && -z "$DMG" ]] ||
   [[ -z "$NOTARY_PROFILE" ]] ||
   [[ -n "$APP" && ! -d "$APP" ]] ||
   [[ -n "$DMG" && ! -f "$DMG" ]]; then
  usage >&2
  exit 2
fi

if [[ -n "$APP" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  ARCHIVE="${APP%.app}.notarization.zip"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  echo "Notarized and stapled: $APP"
  exit 0
fi

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

MOUNTPOINT="$(mktemp -d "${TMPDIR%/}/colerm-dmg.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNTPOINT" >/dev/null 2>&1 || true
  rmdir "$MOUNTPOINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNTPOINT" "$DMG" >/dev/null
[[ -L "$MOUNTPOINT/Applications" ]] &&
  [[ "$(readlink "$MOUNTPOINT/Applications")" == "/Applications" ]] || {
  echo "DMG is missing the /Applications shortcut" >&2
  exit 1
}
codesign --verify --deep --strict --verbose=2 "$MOUNTPOINT/Colerm.app"
spctl --assess --type execute --verbose=4 "$MOUNTPOINT/Colerm.app"
xcrun stapler validate "$MOUNTPOINT/Colerm.app"
echo "Notarized, stapled, and verified: $DMG"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ColermApp"
BUNDLE_ID="com.colerm.app"
DISPLAY_NAME="Colerm"
BIN=""
OUT_APP=""
VERSION=""
BUILD_NUMBER=""
SIGN_IDENTITY=""
SPARKLE_FRAMEWORK=""
SPARKLE_PUBLIC_KEY=""
SPARKLE_FEED_URL=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --bin <path> --out-app <path> [options]

Options:
  --bin <path>       Swift executable to place in Contents/MacOS
  --out-app <path>   Destination .app bundle
  --version <value>  Bundle version (default: VERSION)
  --build-number <value>  Numeric bundle build (default: version digits)
  --sign <identity>  Developer ID identity; omit for ad-hoc signing
  --sparkle-framework <path>  Sparkle.framework to embed
  --sparkle-public-key <key>  Sparkle EdDSA public key
  --sparkle-feed-url <url>    Sparkle appcast URL
  --executable-name <name>  Executable name inside the bundle
  --bundle-id <identifier>  Bundle identifier (default: com.colerm.app)
  --display-name <name>     Finder and Dock name (default: Colerm)
  --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin) BIN="${2:?missing value for --bin}"; shift 2 ;;
    --out-app) OUT_APP="${2:?missing value for --out-app}"; shift 2 ;;
    --version) VERSION="${2:?missing value for --version}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing value for --build-number}"; shift 2 ;;
    --sign) SIGN_IDENTITY="${2:?missing value for --sign}"; shift 2 ;;
    --sparkle-framework) SPARKLE_FRAMEWORK="${2:?missing value for --sparkle-framework}"; shift 2 ;;
    --sparkle-public-key) SPARKLE_PUBLIC_KEY="${2:?missing value for --sparkle-public-key}"; shift 2 ;;
    --sparkle-feed-url) SPARKLE_FEED_URL="${2:?missing value for --sparkle-feed-url}"; shift 2 ;;
    --executable-name) EXECUTABLE_NAME="${2:?missing value for --executable-name}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:?missing value for --bundle-id}"; shift 2 ;;
    --display-name) DISPLAY_NAME="${2:?missing value for --display-name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$BIN" || -z "$OUT_APP" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -f "$BIN" ]]; then
  echo "Executable not found: $BIN" >&2
  exit 1
fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(xargs < "$ROOT/VERSION")"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(tr -cd '0-9' <<<"$VERSION")"
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric: $BUILD_NUMBER" >&2
  exit 1
fi
if [[ -n "$SPARKLE_PUBLIC_KEY" || -n "$SPARKLE_FEED_URL" ]]; then
  if [[ -z "$SPARKLE_PUBLIC_KEY" || -z "$SPARKLE_FEED_URL" ]]; then
    echo "Sparkle public key and feed URL must be provided together" >&2
    exit 1
  fi
fi
if [[ ! -f "$ROOT/Resources/Colerm.icns" ]]; then
  echo "App icon not found: $ROOT/Resources/Colerm.icns" >&2
  echo "Run scripts/prepare_app_icon.sh first." >&2
  exit 1
fi

APP_CONTENTS="$OUT_APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
rm -rf "$OUT_APP"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BIN" "$APP_MACOS/$EXECUTABLE_NAME"

if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
  [[ -d "$SPARKLE_FRAMEWORK" ]] || {
    echo "Sparkle framework not found: $SPARKLE_FRAMEWORK" >&2
    exit 1
  }
  mkdir -p "$APP_FRAMEWORKS"
  ditto "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
fi

if [[ -d "$ROOT/Resources" ]]; then
  cp -R "$ROOT/Resources/." "$APP_RESOURCES/"
fi

GHOSTTY_SHARE="$ROOT/Vendor/ghostty/share"
if [[ -d "$GHOSTTY_SHARE/ghostty" ]]; then
  cp -R "$GHOSTTY_SHARE/ghostty/." "$APP_RESOURCES/"
elif [[ -d "$ROOT/Vendor/ghostty/src/shell-integration" ]]; then
  # The shell integration is required for live PWD/title updates.
  mkdir -p "$APP_RESOURCES/shell-integration"
  cp -R "$ROOT/Vendor/ghostty/src/shell-integration/." \
    "$APP_RESOURCES/shell-integration/"
fi
if [[ -d "$GHOSTTY_SHARE/terminfo" ]]; then
  mkdir -p "$APP_RESOURCES/terminfo"
  cp -R "$GHOSTTY_SHARE/terminfo/." "$APP_RESOURCES/terminfo/"
fi

# Colerm's shell hook is sourced by the bundled Ghostty integration. It emits
# a bounded base64 payload through OSC 777's desktop-notification form; the
# session delegate consumes Colerm-tagged messages instead of notifying users.
COLERM_METADATA_HOOK="$ROOT/Resources/shell-integration/zsh/colerm-node-metadata.zsh"
COLERM_GHOSTTY_ZSH="$APP_RESOURCES/shell-integration/zsh/ghostty-integration"
if [[ ! -f "$COLERM_GHOSTTY_ZSH" ]]; then
  echo "Ghostty zsh shell integration was not packaged: $COLERM_GHOSTTY_ZSH" >&2
  exit 1
fi
if [[ -f "$COLERM_METADATA_HOOK" ]]; then
  {
    printf '%s\n' '' '# Colerm runtime metadata extension.'
    printf '%s\n' 'if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" &&'
    printf '%s\n' '      -f "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/colerm-node-metadata.zsh" ]]; then'
    printf '%s\n' '  source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/colerm-node-metadata.zsh"'
    printf '%s\n' 'fi'
  } >>"$COLERM_GHOSTTY_ZSH"
fi

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">' '<dict>'
  printf '%s\n' '  <key>CFBundleDisplayName</key>' "  <string>$DISPLAY_NAME</string>"
  printf '%s\n' '  <key>CFBundleExecutable</key>' "  <string>$EXECUTABLE_NAME</string>"
  printf '%s\n' '  <key>CFBundleIconFile</key>' '  <string>Colerm.icns</string>'
  printf '%s\n' '  <key>CFBundleIdentifier</key>' "  <string>$BUNDLE_ID</string>"
  printf '%s\n' '  <key>CFBundleName</key>' "  <string>$DISPLAY_NAME</string>"
  printf '%s\n' '  <key>CFBundlePackageType</key>' '  <string>APPL</string>'
  printf '%s\n' '  <key>CFBundleShortVersionString</key>' "  <string>$VERSION</string>"
  printf '%s\n' '  <key>CFBundleVersion</key>' "  <string>$BUILD_NUMBER</string>"
  if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    printf '%s\n' '  <key>SUFeedURL</key>' "  <string>$SPARKLE_FEED_URL</string>"
    printf '%s\n' '  <key>SUPublicEDKey</key>' "  <string>$SPARKLE_PUBLIC_KEY</string>"
    printf '%s\n' '  <key>SUEnableAutomaticChecks</key>' '  <true/>'
    printf '%s\n' '  <key>SUAutomaticallyUpdate</key>' '  <true/>'
    printf '%s\n' '  <key>SURequireSignedFeed</key>' '  <true/>'
    printf '%s\n' '  <key>SUVerifyUpdateBeforeExtraction</key>' '  <true/>'
  fi
  printf '%s\n' '  <key>LSMinimumSystemVersion</key>' '  <string>14.0</string>'
  printf '%s\n' '  <key>NSHighResolutionCapable</key>' '  <true/>' '</dict>' '</plist>'
} >"$APP_CONTENTS/Info.plist"

if [[ -n "$SIGN_IDENTITY" ]]; then
  if [[ -d "$APP_FRAMEWORKS/Sparkle.framework" ]]; then
    codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --preserve-metadata=identifier,entitlements,requirements,flags \
      --sign "$SIGN_IDENTITY" \
      "$APP_FRAMEWORKS/Sparkle.framework"
  fi
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$OUT_APP"
else
  codesign --force --deep --sign - --timestamp=none "$OUT_APP"
fi
codesign --verify --deep --strict "$OUT_APP"

echo "App bundle ready: $OUT_APP"

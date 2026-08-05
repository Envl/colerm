#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="Release"
VERSION="$(xargs < "$ROOT/VERSION")"
SIGN_IDENTITY=""
UNIVERSAL=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --configuration <Debug|Release>  Build configuration (default: Release)
  --version <value>                Bundle version (default: VERSION)
  --sign <identity>                Codesign identity
  --universal                      Build arm64 and x86_64, then create a fat binary
  --help                           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration) CONFIGURATION="${2:?}"; shift 2 ;;
    --version) VERSION="${2:?}"; shift 2 ;;
    --sign) SIGN_IDENTITY="${2:?}"; shift 2 ;;
    --universal) UNIVERSAL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$CONFIGURATION" in
  Debug) SWIFT_CONFIGURATION="debug" ;;
  Release) SWIFT_CONFIGURATION="release" ;;
  *) echo "Unsupported configuration: $CONFIGURATION" >&2; exit 2 ;;
esac

if [[ "$UNIVERSAL" == true ]]; then
  UNIVERSAL_BUILD_ROOT="$ROOT/.build/$SWIFT_CONFIGURATION-universal"
  ARM64_SCRATCH="$UNIVERSAL_BUILD_ROOT/arm64"
  X86_64_SCRATCH="$UNIVERSAL_BUILD_ROOT/x86_64"

  swift build -c "$SWIFT_CONFIGURATION" --triple arm64-apple-macosx --scratch-path "$ARM64_SCRATCH"
  swift build -c "$SWIFT_CONFIGURATION" --triple x86_64-apple-macosx --scratch-path "$X86_64_SCRATCH"

  ARM64_BIN="$(swift build -c "$SWIFT_CONFIGURATION" --triple arm64-apple-macosx --scratch-path "$ARM64_SCRATCH" --show-bin-path)/ColermApp"
  X86_64_BIN="$(swift build -c "$SWIFT_CONFIGURATION" --triple x86_64-apple-macosx --scratch-path "$X86_64_SCRATCH" --show-bin-path)/ColermApp"
  BIN="$ROOT/dist/ColermApp-universal"
  mkdir -p "$ROOT/dist"
  lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$BIN"

  ARCH_INFO="$(lipo -info "$BIN")"
  [[ "$ARCH_INFO" == *arm64* && "$ARCH_INFO" == *x86_64* ]] || {
    echo "Universal binary is missing arm64 or x86_64: $ARCH_INFO" >&2
    exit 1
  }
else
  swift build -c "$SWIFT_CONFIGURATION"
  BIN="$ROOT/.build/$SWIFT_CONFIGURATION/ColermApp"
fi
APP="$ROOT/dist/Colerm.app"

mkdir -p "$ROOT/dist"
BUILD_ARGS=(--bin "$BIN" --out-app "$APP" --version "$VERSION")
if [[ -n "$SIGN_IDENTITY" ]]; then
  BUILD_ARGS+=(--sign "$SIGN_IDENTITY")
fi
"$ROOT/scripts/build_app_bundle.sh" "${BUILD_ARGS[@]}"

printf 'APP_PATH=%s\nVERSION=%s\n' "$APP" "$VERSION"

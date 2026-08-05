#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE=""
SIGN_IDENTITY=""
UNIVERSAL=true
VERSION=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --sign <identity>          Sign the app before packaging
  --notary-profile <name>    Notarize and staple the app and final DMG
  --version <value>          Bundle version (default: VERSION)
  --native                    Build only for the host architecture
  --help                     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) SIGN_IDENTITY="${2:?}"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
    --version) VERSION="${2:?}"; shift 2 ;;
    --native) UNIVERSAL=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

BUILD_ARGS=()
if [[ -n "$SIGN_IDENTITY" ]]; then BUILD_ARGS+=(--sign "$SIGN_IDENTITY"); fi
if [[ "$UNIVERSAL" == true ]]; then BUILD_ARGS+=(--universal); fi
if [[ -n "$VERSION" ]]; then BUILD_ARGS+=(--version "$VERSION"); fi
"$ROOT/scripts/release_step_build.sh" "${BUILD_ARGS[@]}"

APP="$ROOT/dist/Colerm.app"
if [[ -n "$NOTARY_PROFILE" ]]; then
  "$ROOT/scripts/release_step_notarize.sh" --app "$APP" --notary-profile "$NOTARY_PROFILE"
fi

"$ROOT/scripts/release_step_package.sh" --app "$APP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  "$ROOT/scripts/release_step_notarize.sh" \
    --dmg "$ROOT/dist/Colerm.dmg" \
    --notary-profile "$NOTARY_PROFILE"
fi

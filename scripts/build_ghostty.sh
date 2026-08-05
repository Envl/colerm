#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_ROOT="$ROOT/Vendor/ghostty"

usage() {
  cat <<'EOF'
Usage: scripts/build_ghostty.sh

Optionally validate the pinned upstream Ghostty source by building its macOS
GhosttyKit.xcframework and generating resources under Vendor/ghostty/share.

Colerm's normal build uses the exact libghostty-spm package release instead.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
fi

if [[ ! -d "$GHOSTTY_ROOT" ]]; then
  echo "Missing Ghostty submodule: $GHOSTTY_ROOT" >&2
  echo "Run: git submodule update --init --recursive" >&2
  exit 1
fi

ZIG="$(command -v zig || true)"
if [[ -z "$ZIG" ]]; then
  echo "Zig 0.16 is required to build the pinned Ghostty commit." >&2
  echo "Install it with: brew install zig" >&2
  exit 1
fi

ZIG_VERSION="$("$ZIG" version)"
echo "Building Ghostty $(git -C "$GHOSTTY_ROOT" rev-parse HEAD) with Zig $ZIG_VERSION"
cd "$GHOSTTY_ROOT"
"$ZIG" build \
  -Demit-lib-vt=false \
  -Dapp-runtime=none \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=universal \
  -Doptimize=ReleaseFast \
  -p "$GHOSTTY_ROOT"

KIT="$GHOSTTY_ROOT/macos/GhosttyKit.xcframework"
if [[ ! -d "$KIT" ]]; then
  echo "Ghostty build completed without producing $KIT" >&2
  exit 1
fi

echo "GhosttyKit ready: $KIT"

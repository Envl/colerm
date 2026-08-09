#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
TAG=""
REPOSITORY=""
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") --version <version> --tag <tag> --repository <owner/repo>

Reads the Sparkle private key from SPARKLE_ED_PRIVATE_KEY and writes
dist/appcast.xml for the versioned update archive in dist/.

Environment:
  SPARKLE_TOOLS_DIR  Override the directory containing generate_appcast
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --tag) TAG="${2:?missing tag}"; shift 2 ;;
    --repository) REPOSITORY="${2:?missing repository}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$VERSION" && -n "$TAG" && -n "$REPOSITORY" ]] || {
  usage >&2
  exit 2
}
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is required}"

ARCHIVE="$ROOT/dist/Colerm-$VERSION.zip"
[[ -f "$ARCHIVE" ]] || { echo "Update archive not found: $ARCHIVE" >&2; exit 1; }

if [[ -z "$SPARKLE_TOOLS_DIR" ]]; then
  SPARKLE_TOOL_CANDIDATES=(
    "$ROOT/.build/release-universal/arm64/artifacts/sparkle/Sparkle/bin"
    "$ROOT/.build/release-universal/x86_64/artifacts/sparkle/Sparkle/bin"
    "$ROOT/.build/artifacts/sparkle/Sparkle/bin"
  )
  for candidate in "${SPARKLE_TOOL_CANDIDATES[@]}"; do
    if [[ -x "$candidate/generate_appcast" ]]; then
      SPARKLE_TOOLS_DIR="$candidate"
      break
    fi
  done
fi
[[ -x "$SPARKLE_TOOLS_DIR/generate_appcast" ]] || {
  echo "Sparkle generate_appcast tool not found. Set SPARKLE_TOOLS_DIR to its bin directory." >&2
  exit 1
}

UPDATES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/colerm-appcast.XXXXXX")"
trap 'rm -rf "$UPDATES_DIR"' EXIT
cp "$ARCHIVE" "$UPDATES_DIR/"

# Preserve prior entries when one already exists. The first release naturally
# starts a new feed.
curl -fsSL \
  "https://github.com/$REPOSITORY/releases/latest/download/appcast.xml" \
  -o "$UPDATES_DIR/appcast.xml" 2>/dev/null || true

printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_TOOLS_DIR/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  --maximum-deltas 0 \
  "$UPDATES_DIR"

cp "$UPDATES_DIR/appcast.xml" "$ROOT/dist/appcast.xml"
xmllint --noout "$ROOT/dist/appcast.xml"
echo "Sparkle appcast ready: $ROOT/dist/appcast.xml"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(xargs < "$ROOT/VERSION")"

"$ROOT/scripts/release_step_build.sh" \
  --configuration Debug \
  --version "$VERSION"

/usr/bin/pkill -x ColermApp 2>/dev/null || true
while /usr/bin/pgrep -x ColermApp >/dev/null; do
  sleep 0.1
done

open -n "$ROOT/dist/Colerm.app"

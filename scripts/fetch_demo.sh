#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/demo-cache"
ART="$ROOT/artifacts"
ZIP="$CACHE/ft-dos-demo-en.zip"
URL="https://downloads.scummvm.org/frs/demos/scumm/ft-dos-demo-en.zip"

mkdir -p "$CACHE" "$ART"
curl -fL --retry 5 --retry-all-errors --connect-timeout 30 \
  -o "$ZIP.part" "$URL"
mv "$ZIP.part" "$ZIP"

unzip -t "$ZIP" | tee "$ART/demo-zip-test.txt"
sha256sum "$ZIP" | tee "$ART/demo-sha256.txt"
du -h "$ZIP" | tee "$ART/demo-size.txt"

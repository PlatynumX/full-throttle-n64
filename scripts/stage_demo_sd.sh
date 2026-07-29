#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="$ROOT/demo-cache/ft-dos-demo-en.zip"
OUT="$ROOT/artifacts/sdcard/fullthrottle"

test -f "$ZIP"
rm -rf "$OUT"
mkdir -p "$OUT/saves"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" -d "$TMP"

# Flatten a single wrapper directory if the archive has one.
shopt -s dotglob nullglob
items=("$TMP"/*)
if [ "${#items[@]}" -eq 1 ] && [ -d "${items[0]}" ]; then
  cp -a "${items[0]}"/. "$OUT"/
else
  cp -a "$TMP"/. "$OUT"/
fi

mkdir -p "$OUT/saves"
printf 'scumm:ft\n' > "$OUT/Full Throttle.scummvm"
find "$OUT" -maxdepth 2 -type f -printf '%P %s bytes\n' | sort \
  > "$ROOT/artifacts/demo-file-list.txt"

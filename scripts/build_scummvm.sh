#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
PORT="$SCUMMVM/backends/platform/n64libdragon"
ART="$ROOT/artifacts"
mkdir -p "$ART"

set +e
make -C "$PORT" clean
make -C "$PORT" V=1 -j"$(nproc)" 2>&1 | tee "$ART/scummvm-build.log"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -eq 0 ] && [ -f "$PORT/full-throttle-n64-r2.z64" ]; then
  cp "$PORT/full-throttle-n64-r2.z64" "$ART/full-throttle-n64-r2.z64"
  sha256sum "$ART/full-throttle-n64-r2.z64" > "$ART/full-throttle-n64-r2.sha256"
  printf 'PASS\n' > "$ART/scummvm-build-status.txt"
else
  printf 'FAIL rc=%s\n' "$rc" > "$ART/scummvm-build-status.txt"
  # Preserve diagnostics, but return failure so the workflow accurately shows
  # whether the integration ROM built.
  exit "$rc"
fi

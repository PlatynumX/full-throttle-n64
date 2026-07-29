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

if [ "$rc" -eq 0 ] && [ -f "$PORT/full-throttle-n64-r2l.z64" ]; then
  cp "$PORT/full-throttle-n64-r2l.z64" "$ART/full-throttle-n64-r2l.z64"
  sha256sum "$ART/full-throttle-n64-r2l.z64" > "$ART/full-throttle-n64-r2l.sha256"
  printf 'PASS\n' > "$ART/scummvm-build-status.txt"
else
  fail_rc="$rc"
  if [ "$fail_rc" -eq 0 ]; then
    # A successful make without the declared ROM is still a failed build.
    fail_rc=1
  fi
  printf 'FAIL rc=%s\n' "$fail_rc" > "$ART/scummvm-build-status.txt"
  # Preserve diagnostics, but return failure so the workflow accurately shows
  # whether the integration ROM was actually produced.
  exit "$fail_rc"
fi

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
PORT="$SCUMMVM/backends/platform/n64libdragon"
ART="$ROOT/artifacts"
ROM="full-throttle-n64-r2t.z64"
mkdir -p "$ART"

set +e
make -C "$PORT" clean
make -C "$PORT" V=1 -j"$(nproc)" 2>&1 | tee "$ART/scummvm-build.log"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -eq 0 ] && [ -f "$PORT/$ROM" ]; then
    cp "$PORT/$ROM" "$ART/$ROM"
    sha256sum "$ART/$ROM" > "$ART/full-throttle-n64-r2t.sha256"
    printf 'PASS\n' > "$ART/scummvm-build-status.txt"
else
    fail_rc="$rc"
    if [ "$fail_rc" -eq 0 ]; then
        # A successful make without the declared ROM is still a failed build.
        fail_rc=1
    fi
    printf 'FAIL rc=%s\n' "$fail_rc" > "$ART/scummvm-build-status.txt"
    exit "$fail_rc"
fi

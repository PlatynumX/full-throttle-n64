#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ART="$ROOT/artifacts"
mkdir -p "$ART"

make -C "$ROOT/probe" clean
make -C "$ROOT/probe" V=1 2>&1 | tee "$ART/probe-build.log"
cp "$ROOT/probe/ft64-sd-probe-r2v-v17.z64" "$ART/ft64-sd-probe-r2v-v17.z64"
sha256sum "$ART/ft64-sd-probe-r2v-v17.z64" > "$ART/ft64-sd-probe-r2v-v17.sha256"

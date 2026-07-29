#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
SRC="$ROOT/backend"
DST="$SCUMMVM/backends/platform/n64libdragon"

test -d "$SCUMMVM/.git"
rm -rf "$DST"
mkdir -p "$DST"

cp "$SRC/osys_n64_libdragon.h" "$DST/"
cp "$SRC/osys_n64_libdragon.cpp" "$DST/"
cp "$SRC/nintendo64_libdragon.cpp" "$DST/"
cp "$SRC/n64libdragon-fs.h" "$DST/"
cp "$SRC/n64libdragon-fs.cpp" "$DST/"
cp "$SRC/Makefile.libdragon" "$DST/Makefile"

# Evidence gates: Full Throttle's SCUMM v7/v8 module must exist and our
# platform Makefile must enable it. The libdragon backend must not pull in
# ScummVM's POSIX filesystem, because libdragon does not implement dirent.h.
grep -q 'ifdef ENABLE_SCUMM_7_8' "$SCUMMVM/engines/scumm/module.mk"
grep -q 'ENABLE_SCUMM_7_8' "$SCUMMVM/engines/engines.mk"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' "$DST/Makefile"
! grep -R -n 'backends/fs/posix\|<dirent.h>' "$DST"
grep -q '#include <dir.h>' "$DST/n64libdragon-fs.cpp"
grep -q 'dir_findfirst' "$DST/n64libdragon-fs.cpp"

# Intent-to-add makes git diff include the clean new backend files without
# staging their contents or mutating any upstream ScummVM source.
git -C "$SCUMMVM" add -N backends/platform/n64libdragon
git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ROOT/artifacts/r2d-backend.patch"
git -C "$SCUMMVM" status --short > "$ROOT/artifacts/scummvm-status-after-integration.txt"

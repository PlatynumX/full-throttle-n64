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
cp "$SRC/Makefile.libdragon" "$DST/Makefile"

# ScummVM 1.6.0's POSIX FS implementation is exactly the API we need on top
# of libdragon/Newlib, but its compile guard predates this platform.
python3 - "$SCUMMVM" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = [
    root / "backends/fs/posix/posix-fs.cpp",
    root / "backends/fs/posix/posix-fs-factory.cpp",
]
for p in files:
    s = p.read_text()
    old = "#if defined(POSIX) || defined(PLAYSTATION3)"
    new = "#if defined(POSIX) || defined(PLAYSTATION3) || defined(N64_LIBDRAGON)"
    if old not in s:
        raise SystemExit(f"expected POSIX guard not found in {p}")
    s = s.replace(old, new)
    p.write_text(s)
PY

# Hard evidence gates: do not build if the exact engine switches disappeared.
grep -q 'ifdef ENABLE_SCUMM_7_8' "$SCUMMVM/engines/scumm/module.mk"
grep -q 'ENABLE_SCUMM_7_8' "$SCUMMVM/engines/engines.mk"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' "$DST/Makefile"

git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ROOT/artifacts/r2a-backend.patch"

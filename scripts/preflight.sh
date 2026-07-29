#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[preflight] shell syntax"
for f in scripts/*.sh; do
  bash -n "$f"
done

echo "[preflight] required r2a backend gates"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' backend/Makefile.libdragon
grep -q 'N64_LIBDRAGON' backend/Makefile.libdragon
grep -q '^MKDIR := mkdir -p' backend/Makefile.libdragon
grep -q 'filter-out -Werror' backend/Makefile.libdragon
grep -q -- '-std=gnu++11' backend/Makefile.libdragon
grep -q 'DefaultSaveFileManager("sd:/fullthrottle/saves")' backend/osys_n64_libdragon.cpp
grep -q 'DefaultTimerManager \*>(_timerManager)->handler()' backend/osys_n64_libdragon.cpp
grep -q 'get_ticks_ms()' backend/osys_n64_libdragon.cpp
grep -q '"-p"' backend/nintendo64_libdragon.cpp
grep -q '"sd:/fullthrottle"' backend/nintendo64_libdragon.cpp
grep -q '"ft"' backend/nintendo64_libdragon.cpp
grep -q 'assert_memory_expanded();' backend/nintendo64_libdragon.cpp
grep -q 'return (uint16)(src | 1);' backend/osys_n64_libdragon.cpp
grep -q 'is_memory_expanded()' probe/sd_probe.c
grep -q 'get_memory_size()' probe/sd_probe.c

echo "[preflight] no known legacy/freeze traps"
if grep -R -nE 'hkz-libn64|libn64\.h|pakfs|framfs|initRomFSmanager|NONSTANDARD_PORT' backend probe; then
  echo "legacy N64 dependency leaked into r2a backend" >&2
  exit 1
fi
if grep -n 'for *(;;)' backend/osys_n64_libdragon.cpp; then
  echo "infinite quit loop leaked into backend" >&2
  exit 1
fi
if grep -R -n '_timerCallback\|setTimerCallback' backend; then
  echo "obsolete backend-local timer callback leaked into backend" >&2
  exit 1
fi

echo "[preflight] CI does not depend on executable script bits"
if grep -nE 'run: \./scripts/|^[[:space:]]+\./scripts/' .github/workflows/build-full-throttle-r2a.yml; then
  echo "workflow invokes repository scripts directly; use bash ./scripts/... for Android-safe Git modes" >&2
  exit 1
fi
if grep -nE '^\./scripts/' scripts/run_all.sh; then
  echo "run_all.sh invokes repository scripts directly; use bash ./scripts/..." >&2
  exit 1
fi

echo "[preflight] demo and toolchain URLs"
grep -q 'downloads.scummvm.org/frs/demos/scumm/ft-dos-demo-en.zip' scripts/fetch_demo.sh
grep -q 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' .github/workflows/build-full-throttle-r2a.yml
grep -q '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh

echo "[preflight] OK"

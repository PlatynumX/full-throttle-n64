#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[preflight] shell syntax"
for f in scripts/*.sh; do
  bash -n "$f"
done

echo "[preflight] no unresolved merge-conflict markers"
if grep -RInE '^(<<<<<<<|=======|>>>>>>>)' \
    --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts --exclude-dir=demo-cache \
    .github backend probe scripts docs demo README.md TERMUX.md; then
  echo "unresolved Git merge-conflict marker found; refusing to build" >&2
  exit 1
fi

echo "[preflight] required r2d backend gates"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' backend/Makefile.libdragon
grep -q 'N64_LIBDRAGON' backend/Makefile.libdragon
grep -q '^MKDIR := mkdir -p' backend/Makefile.libdragon
grep -q 'filter-out -Werror' backend/Makefile.libdragon
grep -q -- '-std=gnu++11' backend/Makefile.libdragon
grep -q 'N64LibdragonFilesystemFactory' backend/osys_n64_libdragon.cpp
grep -q 'n64libdragon-fs.o' backend/Makefile.libdragon
grep -q '#include <dir.h>' backend/n64libdragon-fs.cpp
grep -q 'dir_findfirst' backend/n64libdragon-fs.cpp
grep -q 'dir_findnext' backend/n64libdragon-fs.cpp
grep -q 'DefaultSaveFileManager("sd:/fullthrottle/saves")' backend/osys_n64_libdragon.cpp
grep -Fq 'static_cast<DefaultTimerManager *>(_timerManager)->handler()' backend/osys_n64_libdragon.cpp
grep -q 'get_ticks_ms()' backend/osys_n64_libdragon.cpp
grep -q '"-p"' backend/nintendo64_libdragon.cpp
grep -q '"sd:/fullthrottle"' backend/nintendo64_libdragon.cpp
grep -q '"ft"' backend/nintendo64_libdragon.cpp
grep -q 'assert_memory_expanded();' backend/nintendo64_libdragon.cpp
grep -q 'return (uint16)(src | 1);' backend/osys_n64_libdragon.cpp
grep -q '^N64_ROM_CONTROLLER1 := n64$' backend/Makefile.libdragon
grep -q '^N64_ROM_CONTROLLER1=n64$' probe/Makefile
grep -Fq 'memset(_game.pixels, 0, _game.pitch * _game.h);' backend/osys_n64_libdragon.cpp
grep -q 'is_memory_expanded()' probe/sd_probe.c
grep -q 'get_memory_size()' probe/sd_probe.c
grep -q '#include <dir.h>' probe/sd_probe.c
grep -q 'dir_findfirst' probe/sd_probe.c
grep -q 'saves/.keep' scripts/stage_demo_sd.sh

echo "[preflight] previous CI regression guards"
if grep -R -nE '^N64_ROM_CONTROLLER1[[:space:]]*[:?+]?=[[:space:]]*joypad$' backend probe; then
  echo "invalid libdragon ROM-header controller metadata leaked into r2d" >&2
  exit 1
fi
if grep -R -n 'getPixels()' backend; then
  echo "newer ScummVM Surface::getPixels API leaked into pinned 1.6.0 backend" >&2
  exit 1
fi

echo "[preflight] no unsupported POSIX directory backend"
if grep -R -nE '<dirent\.h>|opendir\(|readdir\(|closedir\(|backends/fs/posix' backend probe; then
  echo "unsupported POSIX directory dependency leaked into r2d" >&2
  exit 1
fi
if grep -R -nE 'mkdir\("sd:/' backend probe; then
  echo "runtime SD mkdir leaked into r2d; pinned libdragon FAT has no mkdir hook" >&2
  exit 1
fi

echo "[preflight] no known legacy/freeze traps"
if grep -R -nE 'hkz-libn64|libn64\.h|pakfs|framfs|initRomFSmanager|NONSTANDARD_PORT' backend probe; then
  echo "legacy N64 dependency leaked into r2d backend" >&2
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
if grep -nE 'run: \./scripts/|^[[:space:]]+\./scripts/' .github/workflows/build-full-throttle-r2d.yml; then
  echo "workflow invokes repository scripts directly; use bash ./scripts/..." >&2
  exit 1
fi
if grep -nE '^\./scripts/' scripts/run_all.sh; then
  echo "run_all.sh invokes repository scripts directly; use bash ./scripts/..." >&2
  exit 1
fi

echo "[preflight] both N64 compile paths preserve diagnostics"
grep -q 'id: probe' .github/workflows/build-full-throttle-r2d.yml
grep -q 'id: scummvm' .github/workflows/build-full-throttle-r2d.yml
[ "$(grep -c 'continue-on-error: true' .github/workflows/build-full-throttle-r2d.yml)" -eq 2 ]

echo "[preflight] demo and toolchain URLs"
grep -q 'downloads.scummvm.org/frs/demos/scumm/ft-dos-demo-en.zip' scripts/fetch_demo.sh
grep -q 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' .github/workflows/build-full-throttle-r2d.yml
grep -q '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh

echo "[preflight] OK"

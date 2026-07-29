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
    .github backend probe scripts docs demo upstream README.md TERMUX.md .gitattributes; then
  echo "unresolved Git merge-conflict marker found; refusing to build" >&2
  exit 1
fi

echo "[preflight] required r2k backend gates"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' backend/Makefile.libdragon
grep -q 'N64_LIBDRAGON' backend/Makefile.libdragon
grep -q '^MKDIR := mkdir -p' backend/Makefile.libdragon
grep -q 'filter-out -Werror' backend/Makefile.libdragon
grep -q -- '-std=gnu++11' backend/Makefile.libdragon
# libdragon n64.mk owns platform-flag propagation through the %.z64 target.
# Generic flags must contain only port-specific deltas, never a second copy of N64_*.
grep -q '^CFLAGS :=$' backend/Makefile.libdragon
grep -q '^CXXFLAGS := -fno-rtti -fno-exceptions$' backend/Makefile.libdragon
grep -q '^ASFLAGS :=$' backend/Makefile.libdragon
grep -q '^LDFLAGS :=$' backend/Makefile.libdragon
if grep -nE '^(CFLAGS|CXXFLAGS|ASFLAGS|LDFLAGS)[[:space:]]*:=[[:space:]]*.*\$\(N64_(CFLAGS|CXXFLAGS|ASFLAGS|LDFLAGS)\)' backend/Makefile.libdragon; then
  echo "libdragon platform flags are being copied into generic flags; this duplicates target-specific propagation" >&2
  exit 1
fi
grep -Fq 'INCLUDES += -I. -I$(srcdir) -I$(srcdir)/engines' backend/Makefile.libdragon
test -f upstream/scummvm-1.6.0-ft64.patch
grep -Fq -- $'-\tpredictivedialog.o \\' upstream/scummvm-1.6.0-ft64.patch
[ "$(git apply --numstat upstream/scummvm-1.6.0-ft64.patch)" = $'0\t1\tgui/module.mk' ]
if grep -Fq 'filter-out gui/predictivedialog.o' backend/Makefile.libdragon; then
  echo "invalid post-Makefile.common predictive-dialog filter returned" >&2
  exit 1
fi
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
grep -Fqx 'N64_ROM_TITLE := "Full Throttle N64"' backend/Makefile.libdragon
grep -q '^N64_ROM_CONTROLLER1=n64$' probe/Makefile
grep -Fq 'memset(_game.pixels, 0, _game.pitch * _game.h);' backend/osys_n64_libdragon.cpp
grep -q 'is_memory_expanded()' probe/sd_probe.c
grep -q 'get_memory_size()' probe/sd_probe.c
grep -q '#include <dir.h>' probe/sd_probe.c
grep -q 'dir_findfirst' probe/sd_probe.c
grep -q 'saves/.keep' scripts/stage_demo_sd.sh

echo "[preflight] Full Throttle-only engine scope"
if grep -nE '^ENABLE_AGI[[:space:]]*[:?+]?=' backend/Makefile.libdragon; then
  echo "AGI engine unexpectedly enabled; predictive-dialog prune would no longer be safe" >&2
  exit 1
fi

echo "[preflight] previous CI regression guards"
if grep -R -nE '^N64_ROM_CONTROLLER1[[:space:]]*[:?+]?=[[:space:]]*joypad$' backend probe; then
  echo "invalid libdragon ROM-header controller metadata leaked into r2k" >&2
  exit 1
fi
if grep -R -n 'getPixels()' backend; then
  echo "newer ScummVM Surface::getPixels API leaked into pinned 1.6.0 backend" >&2
  exit 1
fi
if grep -nE '^(CFLAGS|CXXFLAGS).*\$\(DEFINES\)' backend/Makefile.libdragon; then
  echo "DEFINES duplicated into compiler flags; Makefile.common supplies them via CPPFLAGS" >&2
  exit 1
fi

echo "[preflight] no unsupported POSIX directory backend"
if grep -R -nE '<dirent\.h>|opendir\(|readdir\(|closedir\(|backends/fs/posix' backend probe; then
  echo "unsupported POSIX directory dependency leaked into r2k" >&2
  exit 1
fi
if grep -R -nE 'mkdir\("sd:/' backend probe; then
  echo "runtime SD mkdir leaked into r2k; pinned libdragon FAT has no mkdir hook" >&2
  exit 1
fi

echo "[preflight] no known legacy/freeze traps"
if grep -R -nE 'hkz-libn64|libn64\.h|pakfs|framfs|initRomFSmanager|NONSTANDARD_PORT' backend probe; then
  echo "legacy N64 dependency leaked into r2k backend" >&2
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
if grep -nE 'run: \./scripts/|^[[:space:]]+\./scripts/' .github/workflows/build-full-throttle-r2k.yml; then
  echo "workflow invokes repository scripts directly; use bash ./scripts/..." >&2
  exit 1
fi
if grep -nE '^\./scripts/' scripts/run_all.sh; then
  echo "run_all.sh invokes repository scripts directly; use bash ./scripts/..." >&2
  exit 1
fi

echo "[preflight] both N64 compile paths preserve diagnostics"
grep -q 'id: probe' .github/workflows/build-full-throttle-r2k.yml
grep -q 'id: scummvm' .github/workflows/build-full-throttle-r2k.yml
[ "$(grep -c 'continue-on-error: true' .github/workflows/build-full-throttle-r2k.yml)" -eq 2 ]

echo "[preflight] no stale operational revision labels"
if grep -RInE 'r2[a-i]|R2[A-I]' .github backend probe scripts demo upstream TERMUX.md; then
  echo "stale prior-revision operational label leaked into r2k" >&2
  exit 1
fi

echo "[preflight] demo and toolchain URLs"
grep -q 'downloads.scummvm.org/frs/demos/scumm/ft-dos-demo-en.zip' scripts/fetch_demo.sh
grep -q 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' .github/workflows/build-full-throttle-r2k.yml
grep -q '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh

echo "[preflight] build result accounting"
grep -q 'fail_rc=1' scripts/build_scummvm.sh
grep -Fq 'if [ "$rc" -eq 0 ] && [ -f "$PORT/full-throttle-n64-r2k.z64" ]; then' scripts/build_scummvm.sh

echo "[preflight] generated-make audit is pipefail-safe"
grep -Fq 'make -C "$DST" -n full-throttle-n64-r2k.z64' scripts/integrate_backend.sh
grep -Fq 'expected exactly one n64.ld linker script flag' scripts/integrate_backend.sh
grep -Fq 'link_block="$(awk' scripts/integrate_backend.sh
grep -Fq 'capture && /-Wl,-Map=build\/full-throttle-n64-r2k\.map;/ { exit }' scripts/integrate_backend.sh
grep -Fq 'package_line="$(awk' scripts/integrate_backend.sh
grep -Fq 'verified n64tool recipe:' scripts/integrate_backend.sh
grep -Fq 'expected_package=' scripts/integrate_backend.sh
grep -Fq 'observed n64tool command:' scripts/integrate_backend.sh
if grep -nE 'grep .*\|[[:space:]]*head|printf .*\|[[:space:]]*grep .*(-q|-Fq)' scripts/integrate_backend.sh; then
  echo "short-circuiting grep/head or printf/grep audit pipeline leaked into r2k" >&2
  exit 1
fi
if grep -nF 'mips64-elf-gcc --version | head' .github/workflows/build-full-throttle-r2k.yml; then
  echo "toolchain version probe still uses a head pipeline under pipefail" >&2
  exit 1
fi

echo "[preflight] OK"

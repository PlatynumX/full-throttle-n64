\
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORKFLOW=".github/workflows/build-full-throttle-r2m.yml"

echo "[preflight] shell syntax"
for f in scripts/*.sh; do
  bash -n "$f"
done

echo "[preflight] required project files"
for f in \
  "$WORKFLOW" \
  backend/Makefile.libdragon \
  backend/osys_n64_libdragon.cpp \
  backend/osys_n64_libdragon.h \
  backend/n64libdragon-fs.cpp \
  backend/n64libdragon-fs.h \
  backend/nintendo64_libdragon.cpp \
  probe/Makefile \
  probe/sd_probe.c \
  upstream/scummvm-1.6.0-ft64.patch; do
  test -f "$f"
done

echo "[preflight] no unresolved merge-conflict markers"
mapfile -t conflict_files < <(
  grep -RIlE '^(<<<<<<<|=======|>>>>>>>)' \
    --exclude-dir=.git --exclude-dir=work --exclude-dir=artifacts \
    .github backend probe scripts docs upstream README.md TERMUX.md .gitattributes 2>/dev/null || true
)
if [ "${#conflict_files[@]}" -ne 0 ]; then
  printf 'unresolved Git conflict marker in: %s\n' "${conflict_files[@]}" >&2
  exit 1
fi

echo "[preflight] r2m identity"
grep -Fqx 'name: Build Full Throttle N64 r2m' "$WORKFLOW"
grep -Fq 'name: full-throttle-n64-r2m-build-report' "$WORKFLOW"
grep -Fq 'TARGET := full-throttle-n64-r2m' backend/Makefile.libdragon
grep -Fq 'full-throttle-n64-r2m.z64' scripts/build_scummvm.sh
grep -Fq 'FT64 r2m: libdragon backend starting' backend/osys_n64_libdragon.cpp
grep -Fq 'FULL THROTTLE N64 - r2m' probe/sd_probe.c

echo "[preflight] no game/demo payload machinery"
test ! -e demo
test ! -e scripts/fetch_demo.sh
test ! -e scripts/stage_demo_sd.sh
if grep -RInE 'ft-dos-demo|fetch_demo|stage_demo|demo-cache|artifacts/sdcard' \
    .github scripts/run_all.sh scripts/publish_termux.sh TERMUX.md .gitignore; then
  echo "game/demo packaging machinery leaked into r2m" >&2
  exit 1
fi

echo "[preflight] pinned source/toolchain"
grep -Fq 'f75a652bb7c956f145abe881c87b5dbf5c9ec24b' scripts/fetch_source.sh
grep -Fq '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh
grep -Fq 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' "$WORKFLOW"

echo "[preflight] Full Throttle-only build scope"
grep -Fq 'ENABLE_SCUMM := $(ENABLED)' backend/Makefile.libdragon
grep -Fq 'ENABLE_SCUMM_7_8 := $(ENABLED)' backend/Makefile.libdragon
if grep -nE '^ENABLE_AGI[[:space:]]*[:?+]?=' backend/Makefile.libdragon; then
  echo "AGI unexpectedly enabled" >&2
  exit 1
fi
[ "$(git apply --numstat upstream/scummvm-1.6.0-ft64.patch)" = $'0\t1\tgui/module.mk' ]

echo "[preflight] established libdragon build contract"
grep -Fq 'N64_ROM_TITLE := "Full Throttle N64"' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1 := n64' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1=n64' probe/Makefile
grep -Fq 'N64_CXXFLAGS := $(filter-out -Werror -std=gnu++17,$(N64_CXXFLAGS)) -std=gnu++11' backend/Makefile.libdragon
grep -Fq 'CFLAGS :=' backend/Makefile.libdragon
grep -Fq 'CXXFLAGS := -fno-rtti -fno-exceptions' backend/Makefile.libdragon
grep -Fq 'LDFLAGS :=' backend/Makefile.libdragon
grep -Fq 'INCLUDES += -I. -I$(srcdir) -I$(srcdir)/engines' backend/Makefile.libdragon

echo "[preflight] r2m input path"
grep -Fq 'sampleAnalogMouse(_joypadInput);' backend/osys_n64_libdragon.cpp
grep -Fq 'const uint32 inputPollMs = 16;' backend/osys_n64_libdragon.cpp
grep -Fq 'const uint32 mouseEventMs = 40;' backend/osys_n64_libdragon.cpp
grep -Fq 'if (sx > 60) sx = 60;' backend/osys_n64_libdragon.cpp
grep -Fq 'if (sy > 60) sy = 60;' backend/osys_n64_libdragon.cpp
grep -Fq 'tan((double)sx * (pi / 140.0))' backend/osys_n64_libdragon.cpp
grep -Fq 'tan((double)sy * (pi / 140.0))' backend/osys_n64_libdragon.cpp
grep -Fq 'const joypad_buttons_t buttons = _joypadInput.btn;' backend/osys_n64_libdragon.cpp
if grep -Fq 'joypad_get_buttons_pressed' backend/osys_n64_libdragon.cpp; then
  echo "event backend still consumes libdragon pressed transitions directly" >&2
  exit 1
fi

echo "[preflight] r2m preconverted game-video path"
grep -Fq 'uint16 *_game16;' backend/osys_n64_libdragon.h
grep -Fq 'void OSystem_N64Libdragon::rebuildGame16()' backend/osys_n64_libdragon.cpp
grep -Fq 'if (!_screenDirty)' backend/osys_n64_libdragon.cpp
grep -Fq 'if (_game16Dirty)' backend/osys_n64_libdragon.cpp
grep -Fq 'memcpy(drow + xoff, srow, _gameW * sizeof(uint16));' backend/osys_n64_libdragon.cpp
grep -Fq '_game16Dirty = true;' backend/osys_n64_libdragon.cpp

echo "[preflight] SD filesystem and save path"
grep -Fq 'debug_init_sdfs("sd:/", -1)' backend/osys_n64_libdragon.cpp
grep -Fq 'DefaultSaveFileManager("sd:/fullthrottle/saves")' backend/osys_n64_libdragon.cpp
grep -Fq '#include <dir.h>' backend/n64libdragon-fs.cpp
grep -Fq 'dir_findfirst' backend/n64libdragon-fs.cpp
if grep -RInE '<dirent\.h>|opendir\(|readdir\(|closedir\(|backends/fs/posix' backend probe; then
  echo "unsupported POSIX directory dependency returned" >&2
  exit 1
fi
if grep -RInE 'mkdir\("sd:/' backend probe; then
  echo "runtime SD mkdir returned; pinned FAT adapter has no mkdir hook" >&2
  exit 1
fi

echo "[preflight] no legacy backend dependencies"
if grep -RInE 'hkz-libn64|libn64\.h|pakfs|framfs|initRomFSmanager|NONSTANDARD_PORT' backend probe; then
  echo "legacy N64 dependency leaked into libdragon backend" >&2
  exit 1
fi
if grep -RIn 'getPixels()' backend; then
  echo "newer ScummVM Surface::getPixels API leaked into pinned 1.6.0 backend" >&2
  exit 1
fi

echo "[preflight] CI script invocation and diagnostics"
if grep -nE 'run: \./scripts/|^[[:space:]]+\./scripts/' "$WORKFLOW"; then
  echo "workflow depends on executable script bits" >&2
  exit 1
fi
grep -Fq 'id: probe' "$WORKFLOW"
grep -Fq 'id: scummvm' "$WORKFLOW"
[ "$(grep -c 'continue-on-error: true' "$WORKFLOW")" -eq 2 ]
grep -Fq 'make -C "$PORT" V=1' scripts/build_scummvm.sh
grep -Fq 'tee "$ART/scummvm-build.log"' scripts/build_scummvm.sh
grep -Fq 'tee "$ART/probe-build.log"' scripts/build_probe.sh
grep -Fq 'fail_rc=1' scripts/build_scummvm.sh

echo "[preflight] integration graph validation"
grep -Fq 'git -C "$SCUMMVM" apply --check "$PATCH"' scripts/integrate_backend.sh
grep -Fq 'make -C "$DST" -pn' scripts/integrate_backend.sh
grep -Fq 'gui/libgui.a' scripts/integrate_backend.sh
grep -Fq 'engines/scumm/libscumm.a' scripts/integrate_backend.sh
if grep -nE 'make -C .* -n |scummvm-dry-run|expected exactly one .*compile command' scripts/integrate_backend.sh; then
  echo "brittle generated-command parser returned" >&2
  exit 1
fi

echo "[preflight] OK"

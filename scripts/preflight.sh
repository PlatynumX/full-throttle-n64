#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORKFLOW=".github/workflows/build-full-throttle-r2s.yml"
PATCH="upstream/scummvm-1.6.0-ft64.patch"

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
    "$PATCH"; do
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

echo "[preflight] r2s identity and no stale r2r/r2q/r2o/r2p/r2n workflow"
test ! -e .github/workflows/build-full-throttle-r2r.yml
test ! -e .github/workflows/build-full-throttle-r2q.yml
test ! -e .github/workflows/build-full-throttle-r2o.yml
test ! -e .github/workflows/build-full-throttle-r2p.yml
test ! -e .github/workflows/build-full-throttle-r2n.yml
grep -Fqx 'name: Build Full Throttle N64 r2s' "$WORKFLOW"
grep -Fq 'name: full-throttle-n64-r2s-build-report' "$WORKFLOW"
grep -Fq 'TARGET := full-throttle-n64-r2s' backend/Makefile.libdragon
grep -Fq 'full-throttle-n64-r2s.z64' scripts/build_scummvm.sh
grep -Fq 'ft64-sd-probe-r2s.z64' scripts/build_probe.sh
grep -Fq 'FULL THROTTLE N64 - r2s' probe/sd_probe.c
# Historical documentation may legitimately mention earlier revisions. Reject only
# Active build/runtime identities must all be r2s. Historical docs may mention earlier releases.
if grep -RInE --exclude=preflight.sh 'full-throttle-n64-r2(n|o|p|q|r)(\.z64|-build-report)|ft64-sd-probe-r2(n|o|p|q|r)|Build Full Throttle N64 r2(n|o|p|q|r)|FULL THROTTLE N64 - r2(n|o|p|q|r)' \
    .github scripts backend/Makefile.libdragon probe TERMUX.md; then
    echo "stale active r2n/r2o/r2p/r2q/r2r project identity remains" >&2
    exit 1
fi

echo "[preflight] no game/demo payload machinery"
test ! -e demo
test ! -e scripts/fetch_demo.sh
test ! -e scripts/stage_demo_sd.sh
if grep -RInE 'ft-dos-demo|fetch_demo|stage_demo|demo-cache|artifacts/sdcard' \
    .github scripts/run_all.sh scripts/publish_termux.sh TERMUX.md .gitignore; then
    echo "game/demo packaging machinery leaked into r2s" >&2
    exit 1
fi

echo "[preflight] pinned source/toolchain"
grep -Fq 'f75a652bb7c956f145abe881c87b5dbf5c9ec24b' scripts/fetch_source.sh
grep -Fq '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh
grep -Fq 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' "$WORKFLOW"

echo "[preflight] one consolidated ScummVM patch"
[ "$(find upstream -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 1 ]
mapfile -t patch_paths < <(git apply --numstat "$PATCH" | awk '{print $3}' | sort)
expected_paths=(
    engines/scumm/insane/insane.cpp
    engines/scumm/resource.cpp
    engines/scumm/smush/smush_player.cpp
    engines/scumm/smush/smush_player.h
    gui/module.mk
)
if [ "${patch_paths[*]}" != "${expected_paths[*]}" ]; then
    echo "unexpected consolidated patch path set" >&2
    printf 'actual:   %s\n' "${patch_paths[*]}" >&2
    printf 'expected: %s\n' "${expected_paths[*]}" >&2
    exit 1
fi
expected_patch_sha='9a90e18017552355e2e75eb0a5615f469273892d316a4e84a51d1157dcfbc041'
actual_patch_sha="$(sha256sum "$PATCH" | awk '{print $1}')"
if [ "$actual_patch_sha" != "$expected_patch_sha" ]; then
    echo "consolidated patch digest does not match validated r2s heap diagnostic patch" >&2
    echo "actual:   $actual_patch_sha" >&2
    echo "expected: $expected_patch_sha" >&2
    exit 1
fi
grep -Fq $'\t_smush_setupsan2 = setupsan2;' "$PATCH"
grep -Fq $'\t_player->setCurVideoFlags(_smush_setupsan2);' "$PATCH"
grep -Fq 'const byte headerMajorVersion = b.readByte();' "$PATCH"
grep -Fq 'video speed override' "$PATCH"
grep -Fq 'setCurVideoFlags' "$PATCH"
grep -Fq '_smush_setupsan2' "$PATCH"
grep -Fq 'subSize >= 0x308' "$PATCH"
grep -Fq '[FT64DIAG r2s] SMUSH begin' "$PATCH"
grep -Fq '[FT64DIAG r2s] SMUSH eof' "$PATCH"
grep -Fq '[FT64DIAG r2s] SMUSH loop-exit' "$PATCH"
grep -Fq '[FT64DIAG r2s] SMUSH released' "$PATCH"
grep -Fq 'ft64_diag_resource_heap("request"' "$PATCH"
grep -Fq 'ft64_diag_resource_heap("after-expire"' "$PATCH"
grep -Fq 'size >= 65536' "$PATCH"
grep -Fq 'predictivedialog.o' "$PATCH"
if grep -Fq 'engines/scumm/insane/insane.h' "$PATCH" || grep -Fq 'engines/scumm/scumm.cpp' "$PATCH"; then
    echo "r2s patch imported unnecessary later-source files" >&2
    exit 1
fi

echo "[preflight] Full Throttle-only build scope"
grep -Fq 'ENABLE_SCUMM := $(ENABLED)' backend/Makefile.libdragon
grep -Fq 'ENABLE_SCUMM_7_8 := $(ENABLED)' backend/Makefile.libdragon
if grep -nE '^ENABLE_AGI[[:space:]]*[:?+]?=' backend/Makefile.libdragon; then
    echo "AGI unexpectedly enabled" >&2
    exit 1
fi

echo "[preflight] established libdragon build contract"
grep -Fq 'N64_ROM_TITLE := "Full Throttle N64"' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1 := n64' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1=n64' probe/Makefile
grep -Fq 'N64_CXXFLAGS := $(filter-out -Werror -std=gnu++17,$(N64_CXXFLAGS)) -std=gnu++11' backend/Makefile.libdragon
grep -Fq 'CFLAGS :=' backend/Makefile.libdragon
grep -Fq 'CXXFLAGS := -fno-rtti -fno-exceptions' backend/Makefile.libdragon
grep -Fq 'LDFLAGS :=' backend/Makefile.libdragon
grep -Fq 'INCLUDES += -I. -I$(srcdir) -I$(srcdir)/engines' backend/Makefile.libdragon

echo "[preflight] retained hardware-proven r2m input path"
grep -Fq 'sampleAnalogMouse(_joypadInput);' backend/osys_n64_libdragon.cpp
grep -Fq 'const uint32 inputPollMs = 16;' backend/osys_n64_libdragon.cpp
grep -Fq 'const uint32 mouseEventMs = 40;' backend/osys_n64_libdragon.cpp

echo "[preflight] retained preconverted game-video path"
grep -Fq 'uint16 *_game16;' backend/osys_n64_libdragon.h
grep -Fq 'void OSystem_N64Libdragon::rebuildGame16()' backend/osys_n64_libdragon.cpp
grep -Fq 'if (_game16Dirty)' backend/osys_n64_libdragon.cpp
grep -Fq 'memcpy(drow + xoff, srow, _gameW * sizeof(uint16));' backend/osys_n64_libdragon.cpp

echo "[preflight] SummerCart runtime and heap diagnostics"
grep -Fq '[FT64DIAG r2s] BOOT backend starting' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2s] HB src=poll' backend/osys_n64_libdragon.cpp
grep -Fq 'void ft64_diag_resource_heap(' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2s] RES phase=' backend/osys_n64_libdragon.cpp
grep -Fq 'sys_get_heap_stats(&stats);' backend/osys_n64_libdragon.cpp
grep -Fq 'sys_get_heap_stats(&heap);' backend/osys_n64_libdragon.cpp
grep -Fq 'heap=%d/%d free=%d' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2s] OVL hide' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2s] FS MISS' backend/n64libdragon-fs.cpp
grep -Fq '[FT64DIAG r2s] FS READ open' backend/n64libdragon-fs.cpp
grep -Fq 'kDiagFsMissLimit = 96' backend/n64libdragon-fs.cpp
grep -Fq 'kDiagFsOpLimit = 192' backend/n64libdragon-fs.cpp
grep -Fq 'sc64-termux-log/sc64-listen' scripts/record_sc64_log.sh
grep -Fq 'ft64-sc64-' scripts/record_sc64_log.sh
if grep -RInF 'FT64 r2p:' backend; then
    echo "stale pre-diagnostic backend log identity remains" >&2
    exit 1
fi

echo "[preflight] retained overlay transition correction"
grep -Fq 'void OSystem_N64Libdragon::showOverlay()' backend/osys_n64_libdragon.cpp
grep -Fq 'void OSystem_N64Libdragon::hideOverlay()' backend/osys_n64_libdragon.cpp
grep -Fq 'void OSystem_N64Libdragon::clearOverlay()' backend/osys_n64_libdragon.cpp
grep -Fq 'dst[x] = (uint16)(src[x] & 0xFFFE);' backend/osys_n64_libdragon.cpp
grep -A20 -F 'void OSystem_N64Libdragon::hideOverlay()' backend/osys_n64_libdragon.cpp | grep -Fq 'updateScreen();'
if grep -A8 -F 'void OSystem_N64Libdragon::clearOverlay()' backend/osys_n64_libdragon.cpp | grep -Fq 'memset(_overlay, 0' && \
   ! grep -A35 -F 'void OSystem_N64Libdragon::clearOverlay()' backend/osys_n64_libdragon.cpp | grep -Fq '_game16'; then
    echo "clearOverlay reverted to a black-only implementation" >&2
    exit 1
fi

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
grep -Fq 'set -o pipefail' "$WORKFLOW"
grep -Fq 'tee artifacts/integration.log' "$WORKFLOW"
grep -Fq 'id: probe' "$WORKFLOW"
grep -Fq 'id: scummvm' "$WORKFLOW"
[ "$(grep -c 'continue-on-error: true' "$WORKFLOW")" -eq 2 ]
grep -Fq 'make -C "$PORT" V=1' scripts/build_scummvm.sh
grep -Fq 'tee "$ART/scummvm-build.log"' scripts/build_scummvm.sh
grep -Fq 'tee "$ART/probe-build.log"' scripts/build_probe.sh

echo "[preflight] integration evidence gates"
grep -Fq 'git -C "$SCUMMVM" apply --check "$PATCH"' scripts/integrate_backend.sh
[ "$(grep -Fc 'git -C "$SCUMMVM" apply "$PATCH"' scripts/integrate_backend.sh)" -eq 1 ]
grep -Fq 'smush-header-before.txt' scripts/integrate_backend.sh
grep -Fq 'smush-header-after.txt' scripts/integrate_backend.sh
grep -Fq 'smush-runtime-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'resource-heap-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'resource-create-after.txt' scripts/integrate_backend.sh
grep -Fq 'backend-runtime-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'make -C "$DST" -pn' scripts/integrate_backend.sh
grep -Fq 'gui/libgui.a' scripts/integrate_backend.sh
grep -Fq 'engines/scumm/libscumm.a' scripts/integrate_backend.sh
if grep -nE 'make -C .* -n |scummvm-dry-run|expected exactly one .*compile command|git apply --3way|patch -p' scripts/integrate_backend.sh; then
    echo "brittle/fuzzy integration fallback returned" >&2
    exit 1
fi

echo "[preflight] OK"

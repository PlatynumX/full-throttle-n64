#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; printf "[preflight] FAILED line %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2; exit "$rc"' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORKFLOW=".github/workflows/build-full-throttle-r2v.yml"
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

echo "[preflight] r2v identity and no stale r2u/r2t/r2s/r2r/r2q/r2o/r2p/r2n workflow"
test ! -e .github/workflows/build-full-throttle-r2u.yml
test ! -e .github/workflows/build-full-throttle-r2t.yml
test ! -e .github/workflows/build-full-throttle-r2s.yml
test ! -e .github/workflows/build-full-throttle-r2r.yml
test ! -e .github/workflows/build-full-throttle-r2q.yml
test ! -e .github/workflows/build-full-throttle-r2o.yml
test ! -e .github/workflows/build-full-throttle-r2p.yml
test ! -e .github/workflows/build-full-throttle-r2n.yml
grep -Fqx 'name: Build Full Throttle N64 r2v v20' "$WORKFLOW"
grep -Fq 'name: full-throttle-n64-r2v-v20-build-report' "$WORKFLOW"
grep -Fq 'TARGET := full-throttle-n64-r2v-v20' backend/Makefile.libdragon
grep -Fq 'full-throttle-n64-r2v-v20.z64' scripts/build_scummvm.sh
grep -Fq 'ft64-sd-probe-r2v-v20.z64' scripts/build_probe.sh
grep -Fq 'FULL THROTTLE N64 - r2v-v20' probe/sd_probe.c
# Historical documentation may legitimately mention earlier revisions. Reject only
# Active build/runtime identities must all be r2v. Historical docs may mention earlier releases.
if grep -RInE --exclude=preflight.sh 'full-throttle-n64-r2(n|o|p|q|r|s|t|u)(\.z64|-build-report)|ft64-sd-probe-r2(n|o|p|q|r|s|t|u)|Build Full Throttle N64 r2(n|o|p|q|r|s|t|u)|FULL THROTTLE N64 - r2(n|o|p|q|r|s|t|u)' \
    .github scripts backend/Makefile.libdragon probe TERMUX.md; then
    echo "stale active r2n/r2o/r2p/r2q/r2r/r2s/r2t/r2u project identity remains" >&2
    exit 1
fi

echo "[preflight] no game/demo payload machinery"
test ! -e demo
test ! -e scripts/fetch_demo.sh
test ! -e scripts/stage_demo_sd.sh
if grep -RInE 'ft-dos-demo|fetch_demo|stage_demo|demo-cache|artifacts/sdcard' \
    .github scripts/run_all.sh scripts/publish_termux.sh TERMUX.md .gitignore; then
    echo "game/demo packaging machinery leaked into r2v" >&2
    exit 1
fi

echo "[preflight] pinned source/toolchain"
grep -Fq 'f75a652bb7c956f145abe881c87b5dbf5c9ec24b' scripts/fetch_source.sh
grep -Fq '35f85a0797324a5ed0c723203e33ab3c1da94fdd' scripts/fetch_libdragon.sh
grep -Fq 'toolchain-continuous-prerelease/gcc-toolchain-mips64-x86_64.deb' "$WORKFLOW"

echo "[preflight] exact runtime patch plus deterministic FT-only specializer"
[ "$(find upstream -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 1 ]
mapfile -t patch_paths < <(git apply --numstat "$PATCH" | awk '{print $3}' | sort)
expected_paths=(
    engines/scumm/insane/insane.cpp
    engines/scumm/smush/smush_player.cpp
    engines/scumm/smush/smush_player.h
    gui/module.mk
)
if [ "${patch_paths[*]}" != "${expected_paths[*]}" ]; then
    echo "unexpected exact runtime patch path set" >&2
    printf 'actual:   %s\n' "${patch_paths[*]}" >&2
    printf 'expected: %s\n' "${expected_paths[*]}" >&2
    exit 1
fi

expected_patch_sha='a7615a68561b8977b982aa3a9bbaa229a6ab2b059f7ea0cc180391af114441cf'
actual_patch_sha="$(sha256sum "$PATCH" | awk '{print $1}')"
if [ "$actual_patch_sha" != "$expected_patch_sha" ]; then
    echo "runtime patch digest does not match validated r2v patch" >&2
    echo "actual:   $actual_patch_sha" >&2
    echo "expected: $expected_patch_sha" >&2
    exit 1
fi

SPECIALIZER="scripts/specialize_ft_only.py"
test -f "$SPECIALIZER"
python3 - "$SPECIALIZER" <<'PYCOMPILE'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_bytes()
compile(source, sys.argv[1], "exec")
PYCOMPILE
# Validate the specializer by syntax and required structural behavior below,
# not by a copied digest that must be rewritten whenever the script changes.

grep -Fq $'\t_smush_setupsan2 = setupsan2;' "$PATCH"
grep -Fq $'\t_player->setCurVideoFlags(_smush_setupsan2);' "$PATCH"
grep -Fq 'const byte headerMajorVersion = b.readByte();' "$PATCH"
grep -Fq 'video speed override' "$PATCH"
grep -Fq 'setCurVideoFlags' "$PATCH"
grep -Fq '_smush_setupsan2' "$PATCH"
grep -Fq 'subSize >= 0x308' "$PATCH"
grep -Fq '[FT64DIAG r2v] SMUSH begin' "$PATCH"
grep -Fq '[FT64DIAG r2v] SMUSH eof' "$PATCH"
grep -Fq '[FT64DIAG r2v] SMUSH loop-exit' "$PATCH"
grep -Fq '[FT64DIAG r2v] SMUSH released' "$PATCH"
grep -Fq 'extern void ft64_diag_heap_marker(const char *tag);' "$PATCH"
grep -Fq '::ft64_diag_heap_marker("smush-begin");' "$PATCH"
grep -Fq '::ft64_diag_heap_marker("smush-before-release");' "$PATCH"
grep -Fq '::ft64_diag_heap_marker("smush-after-release");' "$PATCH"
grep -Fq 'predictivedialog.o' "$PATCH"

if grep -Fq 'engines/scumm/resource.cpp' "$PATCH"; then
    echo "resource.cpp unexpectedly returned to the runtime patch" >&2
    exit 1
fi
if grep -Fq 'engines/scumm/insane/insane.h' "$PATCH"; then
    echo "runtime patch imported unnecessary later-source insane.h" >&2
    exit 1
fi
if grep -Eq '^diff --git a/(base/main.cpp|engines/scumm/detection.cpp|engines/scumm/scumm.cpp)' "$PATCH"; then
    echo "large-file specialization leaked back into the runtime patch" >&2
    exit 1
fi

grep -Fq 'find_braced_region' "$SPECIALIZER"
grep -Fq 'find_preprocessor_end' "$SPECIALIZER"
grep -Fq 'expected one stripped-line match' "$SPECIALIZER"
grep -Fq 'FT64 r2v structural:' "$SPECIALIZER"
grep -Fq '"guard launcher function"' "$SPECIALIZER"
grep -Fq 'fixed Full Throttle v7 engine dispatch' "$SPECIALIZER"
grep -Fq 'fixed GDI constructor' "$SPECIALIZER"
grep -Fq 'guard CD audio setup' "$SPECIALIZER"
grep -Fq 'fixed sound manager' "$SPECIALIZER"
grep -Fq 'disable generic MIDI-era music setup' "$SPECIALIZER"
grep -Fq 'N64 resource cache threshold' "$SPECIALIZER"
grep -Fq '_res->setHeapThreshold(400000, 550000);' "$SPECIALIZER"
grep -Fq 'def transform_resource(lines: list[str]) -> list[str]:' "$SPECIALIZER"
grep -Fq 'def transform_script_v6(lines: list[str]) -> list[str]:' "$SPECIALIZER"
grep -Fq 'resource post-expire probe' "$SPECIALIZER"
grep -Fq 'resource eviction' "$SPECIALIZER"
grep -Fq 'video opcode intent diagnostic' "$SPECIALIZER"
grep -Fq 'SMUSH opcode diagnostic' "$SPECIALIZER"
grep -Fq 'INSANE opcode diagnostic' "$SPECIALIZER"
grep -Fq 'ft64_diag_resource_event' "$SPECIALIZER"
grep -Fq 'ft64_diag_video_opcode' "$SPECIALIZER"
grep -Fq 'guard debugger frame hook' "$SPECIALIZER"
grep -Fq 'guard Towns volume hook' "$SPECIALIZER"
grep -Fq 'res.game.id != GID_FT || res.game.version != 7 || res.game.heversion != 0' "$SPECIALIZER"
grep -Fq '_sound->_musicType = MDT_NONE;' "$SPECIALIZER"
grep -Fq '_costumeRenderer = new AkosRenderer(this);' "$SPECIALIZER"
grep -Fq '_actors[i] = new Actor(this, i);' "$SPECIALIZER"
grep -Fq 'mode.add_argument("--check"' "$SPECIALIZER"
grep -Fq 'mode.add_argument("--apply"' "$SPECIALIZER"
grep -Fq 'mode.add_argument("--verify"' "$SPECIALIZER"


echo "[preflight] v20 universal FT audio streaming"
test -f scripts/stream_ft_audio.py
python3 -m py_compile scripts/stream_ft_audio.py
grep -Fq 'openFTSoundStream' scripts/stream_ft_audio.py
grep -Fq '_fileHandle->getName()' scripts/stream_ft_audio.py
grep -Fq "MKTAG('C','r','e','a')" scripts/stream_ft_audio.py
grep -Fq 'kFT64StreamCacheSize = 32768' scripts/stream_ft_audio.py
grep -Fq '"stream-open-failed"' scripts/stream_ft_audio.py
grep -Fq 'STREAMER="$ROOT/scripts/stream_ft_audio.py"' scripts/integrate_backend.sh
grep -Fq 'python3 "$STREAMER" --check "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$STREAMER" --apply "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$STREAMER" --verify "$SCUMMVM"' scripts/integrate_backend.sh
test -f scripts/stream_ft_audio_handles.py
python3 -m py_compile scripts/stream_ft_audio_handles.py
grep -Fq 'streamCacheCapacity' scripts/stream_ft_audio_handles.py
grep -Fq '"stream-prefill"' scripts/stream_ft_audio_handles.py
grep -Fq '"stream-reopen"' scripts/stream_ft_audio_handles.py
grep -Fq 'HANDLE_STREAMER="$ROOT/scripts/stream_ft_audio_handles.py"' scripts/integrate_backend.sh
grep -Fq 'python3 "$HANDLE_STREAMER" --check "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$HANDLE_STREAMER" --apply "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$HANDLE_STREAMER" --verify "$SCUMMVM"' scripts/integrate_backend.sh
if grep -Eq 'ft64LargeSoundArena|sound-633-stop' scripts/specialize_ft_only.py; then
    echo "arena/forced Sound-633 code remains in v20 specializer" >&2
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
grep -Fq -- '-DN64_FT_ONLY' backend/Makefile.libdragon
grep -Fq -- '-DDISABLE_HELP' backend/Makefile.libdragon
grep -Fq -- '-DDISABLE_TOWNS_DUAL_LAYER_MODE' backend/Makefile.libdragon
grep -Fq 'N64_ROM_TITLE := "FT64 R2V V20"' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1 := n64' backend/Makefile.libdragon
grep -Fq 'N64_ROM_CONTROLLER1=n64' probe/Makefile
grep -Fq 'N64_ROM_TITLE="FT64 R2V V20 PROBE"' probe/Makefile
grep -Fq 'all: ft64-sd-probe-r2v-v20.z64' probe/Makefile
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

echo "[preflight] SummerCart runtime and allocator diagnostics"
grep -Fq '[FT64DIAG r2v] BOOT backend starting' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] HB src=poll' backend/osys_n64_libdragon.cpp
grep -Fq 'static const size_t kFt64DiagLargeAllocation = 16384;' backend/osys_n64_libdragon.cpp
grep -Fq 'void *operator new(size_t size)' backend/osys_n64_libdragon.cpp
grep -Fq 'void *operator new[](size_t size)' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] NEW seq=%u phase=%s kind=%s size=%u' backend/osys_n64_libdragon.cpp
grep -Fq 'caller=%p heap=%d/%d free=%d' backend/osys_n64_libdragon.cpp
grep -Fq 'void ft64_diag_heap_marker(const char *tag)' backend/osys_n64_libdragon.cpp
grep -Fq 'void ft64_diag_resource_event(const char *phase' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] RES phase=%s type=%s typeId=%d id=%d' backend/osys_n64_libdragon.cpp
grep -Fq 'contiguous=%d probe=%p heap=%d/%d free=%d' backend/osys_n64_libdragon.cpp
grep -Fq 'strcmp(phase, "post-expire") == 0' backend/osys_n64_libdragon.cpp
grep -Fq 'void ft64_diag_video_opcode(const char *fileName' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] VIDEO opcode=c9 sub=6 file=%s script=%d' backend/osys_n64_libdragon.cpp
grep -Fq 'expanded=%d physical=%u ' backend/osys_n64_libdragon.cpp
grep -Fq 'outside=%u heap=%d/%d free=%d' backend/osys_n64_libdragon.cpp
grep -Fq '__builtin_return_address(0)' backend/osys_n64_libdragon.cpp
grep -Fq 'ft64_diag_heap_marker("ctor-display");' backend/osys_n64_libdragon.cpp
grep -Fq 'DEPTH_16_BPP, 2, GAMMA_NONE' backend/osys_n64_libdragon.cpp
if grep -Fq 'DEPTH_16_BPP, 3, GAMMA_NONE' backend/osys_n64_libdragon.cpp; then
    echo "triple buffering returned" >&2
    exit 1
fi
grep -Fq 'ft64_diag_heap_marker("ctor-audio");' backend/osys_n64_libdragon.cpp
grep -Fq 'ft64_diag_heap_marker("initBackend-mixer");' backend/osys_n64_libdragon.cpp
grep -Fq 'ft64_diag_heap_marker("initSize-after-free");' backend/osys_n64_libdragon.cpp
grep -Fq 'ft64_diag_new(sequence, "failed", kind, size, 0, caller, true);' backend/osys_n64_libdragon.cpp
grep -Fq 'abort();' backend/osys_n64_libdragon.cpp
grep -Fq 's_ft64AllocatorDiagReady = true;' backend/osys_n64_libdragon.cpp
if grep -Fq 'throw ' backend/osys_n64_libdragon.cpp; then
    echo "allocator diagnostics use exceptions despite -fno-exceptions" >&2
    exit 1
fi
grep -Fq 'sys_get_heap_stats(&heap);' backend/osys_n64_libdragon.cpp
grep -Fq 'heap=%d/%d free=%d' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] OVL hide' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] FS MISS' backend/n64libdragon-fs.cpp
grep -Fq '[FT64DIAG r2v] FS READ open' backend/n64libdragon-fs.cpp
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
grep -Fq 'ConfMan.set("savepath", "sd:/fullthrottle");' backend/osys_n64_libdragon.cpp
grep -Fq 'DefaultSaveFileManager("sd:/fullthrottle")' backend/osys_n64_libdragon.cpp
grep -Fq '[FT64DIAG r2v] SAVE path=sd:/fullthrottle' backend/osys_n64_libdragon.cpp
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
grep -Fq 'full-throttle-n64-r2v-v20.elf' scripts/build_scummvm.sh
grep -Fq 'mips64-elf-size -A "$ELF"' scripts/build_scummvm.sh
grep -Fq 'mips64-elf-readelf -S -W "$ELF"' scripts/build_scummvm.sh
grep -Fq 'mips64-elf-nm -S -n --defined-only "$ELF"' scripts/build_scummvm.sh
grep -Fq 'r2v-largest-400-symbols.txt' scripts/build_scummvm.sh
grep -Fq 'r2v-static-memory-summary.txt' scripts/build_scummvm.sh
grep -Fq 'r2v-size-comparison.txt' scripts/build_scummvm.sh
grep -Fq 'r2v-pruned-symbol-audit.txt' scripts/build_scummvm.sh
grep -Fq 'full-throttle-n64-r2v-v20.map' scripts/build_scummvm.sh

echo "[preflight] integration evidence gates"
grep -Fq 'git -C "$SCUMMVM" apply --check --verbose "$PATCH"' scripts/integrate_backend.sh
[ "$(grep -Fc 'git -C "$SCUMMVM" apply "$PATCH"' scripts/integrate_backend.sh)" -eq 1 ]
grep -Fq 'python3 "$SPECIALIZER" --check "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$SPECIALIZER" --apply "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'python3 "$SPECIALIZER" --verify "$SCUMMVM"' scripts/integrate_backend.sh
grep -Fq 'git -C "$SCUMMVM" diff --check' scripts/integrate_backend.sh
if grep -Fq 'FT64 r2v structural: sound 633 transition recovery' scripts/integrate_backend.sh || \
   grep -Fq 'FT64 r2v structural: large sound allocation recovery' scripts/integrate_backend.sh || \
   grep -Fq '"large-sound-purge"' scripts/integrate_backend.sh || \
   grep -Fq '"large-sound-retry"' scripts/integrate_backend.sh; then
    echo "stale v15 generated-resource assertions remain in integrator" >&2
    exit 1
fi
grep -Fq 'smush-header-before.txt' scripts/integrate_backend.sh
grep -Fq 'base-main-before.txt' scripts/integrate_backend.sh
grep -Fq 'scumm-detection-before.txt' scripts/integrate_backend.sh
grep -Fq 'scumm-core-before.txt' scripts/integrate_backend.sh
grep -Fq 'smush-header-after.txt' scripts/integrate_backend.sh
grep -Fq 'smush-runtime-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'backend-runtime-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'ft64_allocate_or_abort' scripts/integrate_backend.sh
if grep -Fq 'ft64_diag_resource_heap' backend/osys_n64_libdragon.cpp upstream/scummvm-1.6.0-ft64.patch; then
    echo "obsolete resource.cpp heap bridge remains" >&2
    exit 1
fi
grep -Fq 'backend-osys-r2v.cpp' scripts/integrate_backend.sh
grep -Fq '::ft64_diag_heap_marker("smush-after-release");' scripts/integrate_backend.sh
grep -Fq '__builtin_return_address(0)' scripts/integrate_backend.sh
grep -Fq 'backend-runtime-diagnostic-markers.txt' scripts/integrate_backend.sh
grep -Fq 'make -C "$DST" -pn' scripts/integrate_backend.sh
grep -Fq 'gui/libgui.a' scripts/integrate_backend.sh
grep -Fq 'engines/scumm/libscumm.a' scripts/integrate_backend.sh
if grep -nE 'make -C .* -n |scummvm-dry-run|expected exactly one .*compile command|git apply --3way|patch -p|sed -i|perl -pi' scripts/integrate_backend.sh scripts/specialize_ft_only.py; then
    echo "brittle/fuzzy integration fallback returned" >&2
    exit 1
fi

echo "[preflight] OK"

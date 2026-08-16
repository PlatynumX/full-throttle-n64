#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; printf "[integrate] FAILED line %s: %s (rc=%s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2; exit "$rc"' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
SRC="$ROOT/backend"
DST="$SCUMMVM/backends/platform/n64libdragon"
PATCH="$ROOT/upstream/scummvm-1.6.0-ft64.patch"
SPECIALIZER="$ROOT/scripts/specialize_ft_only.py"
VERIFIER="$ROOT/scripts/verify_v18_resource.py"
ART="$ROOT/artifacts"
PINNED_SCUMMVM="f75a652bb7c956f145abe881c87b5dbf5c9ec24b"

mkdir -p "$ART/pristine-source" "$ART/patched-source"
test -d "$SCUMMVM/.git"
actual="$(git -C "$SCUMMVM" rev-parse HEAD)"
if [ "$actual" != "$PINNED_SCUMMVM" ]; then
    echo "unexpected ScummVM source: $actual" >&2
    exit 1
fi

git -C "$SCUMMVM" status --short > "$ART/scummvm-pristine-status.txt"
if [ -s "$ART/scummvm-pristine-status.txt" ]; then
    echo "pinned ScummVM checkout is not pristine before integration" >&2
    cat "$ART/scummvm-pristine-status.txt" >&2
    exit 1
fi

# Preserve the exact pristine files touched by the one source patch.
for rel in \
    base/main.cpp \
    gui/module.mk \
    engines/scumm/detection.cpp \
    engines/scumm/scumm.cpp \
    engines/scumm/resource.cpp \
    engines/scumm/script_v6.cpp \
    engines/scumm/insane/insane.cpp \
    engines/scumm/smush/smush_player.cpp \
    engines/scumm/smush/smush_player.h; do
    mkdir -p "$ART/pristine-source/$(dirname "$rel")"
    cp "$SCUMMVM/$rel" "$ART/pristine-source/$rel"
done

# Focused source neighborhoods make a failed CI run useful instead of opaque.
sed -n '1,120p;330,475p' "$SCUMMVM/base/main.cpp" > "$ART/base-main-before.txt"
sed -n '1025,1120p' "$SCUMMVM/engines/scumm/detection.cpp" > "$ART/scumm-detection-before.txt"
sed -n '95,140p;600,620p;1125,1180p;1260,1410p;1605,1800p;1848,1872p' "$SCUMMVM/engines/scumm/scumm.cpp" > "$ART/scumm-core-before.txt"
sed -n '20,60p;748,790p;965,1020p' "$SCUMMVM/engines/scumm/resource.cpp" > "$ART/scumm-resource-before.txt"
sed -n '20,50p;2378,2420p' "$SCUMMVM/engines/scumm/script_v6.cpp" > "$ART/scumm-video-opcode-before.txt"
sed -n '1,45p' "$SCUMMVM/gui/module.mk" > "$ART/gui-module-before.txt"
sed -n '205,250p;895,955p' "$SCUMMVM/engines/scumm/smush/smush_player.cpp" > "$ART/smush-player-before.txt"
sed -n '30,115p' "$SCUMMVM/engines/scumm/smush/smush_player.h" > "$ART/smush-header-before.txt"
sed -n '850,880p;1398,1465p' "$SCUMMVM/engines/scumm/insane/insane.cpp" > "$ART/insane-before.txt"

if [ "$(grep -c '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk")" -ne 1 ]; then
    echo "expected exactly one predictivedialog.o entry in pristine gui/module.mk" >&2
    exit 1
fi
grep -Fq 'int16 _smush_setupsan2;' "$SCUMMVM/engines/scumm/insane/insane.h"
grep -Fq '/* _version = */ b.readUint16LE();' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'bool _skipPalette;' "$SCUMMVM/engines/scumm/smush/smush_player.h"
grep -Fq 'switch (res.game.version)' "$SCUMMVM/engines/scumm/detection.cpp"
grep -Fq '_debugger = new ScummDebugger(this);' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq 'GUI::LauncherDialog dlg;' "$SCUMMVM/base/main.cpp"

# The four small, previously validated INSANE/SMUSH/GUI changes remain one
# exact patch. The five pinned files are specialized by a deterministic
# one-match transformer: every source block must occur exactly once or the
# build stops before compilation. There is no fuzzy apply or --3way fallback.
echo "[integrate] checking exact four-file r2v runtime patch"
git -C "$SCUMMVM" apply --check --verbose "$PATCH"
echo "[integrate] applying exact four-file r2v runtime patch"
git -C "$SCUMMVM" apply "$PATCH"

echo "[integrate] checking structural Full Throttle-only source specialization"
python3 "$SPECIALIZER" --check "$SCUMMVM"
echo "[integrate] applying structural Full Throttle-only source specialization"
python3 "$SPECIALIZER" --apply "$SCUMMVM"
python3 "$SPECIALIZER" --verify "$SCUMMVM"
git -C "$SCUMMVM" diff --check

# Verify source-level results, not merely a zero exit code.
if grep -q '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk"; then
    echo "predictivedialog.o remained in GUI module after patch" >&2
    exit 1
fi
grep -Fq 'int16 _curVideoFlags;' "$SCUMMVM/engines/scumm/smush/smush_player.h"
grep -Fq 'void setCurVideoFlags(int16 flags);' "$SCUMMVM/engines/scumm/smush/smush_player.h"
grep -Fq '_curVideoFlags = 0;' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'headerMajorVersion > 1 && subSize >= 0x308' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'video speed override' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'b.skip(0x300);' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2v] SMUSH begin' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2v] SMUSH eof' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2v] SMUSH loop-exit' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2v] SMUSH released' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'extern void ft64_diag_heap_marker(const char *tag);' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-begin");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-before-release");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-after-release");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '#ifdef N64_FT_ONLY' "$SCUMMVM/engines/scumm/detection.cpp"
grep -Fq 'res.game.id != GID_FT || res.game.version != 7' "$SCUMMVM/engines/scumm/detection.cpp"
grep -Fq '_gdi = new Gdi(this);' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq '_sound = new Sound(this, _mixer);' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq '_charset = new CharsetRendererClassic(this);' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq '_costumeRenderer = new AkosRenderer(this);' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq '_sound->_musicType = MDT_NONE;' "$SCUMMVM/engines/scumm/scumm.cpp"
grep -Fq 'ft64_diag_resource_event' "$SCUMMVM/engines/scumm/resource.cpp"
grep -Fq '"post-expire"' "$SCUMMVM/engines/scumm/resource.cpp"
python3 "$VERIFIER" "$SCUMMVM/engines/scumm/resource.cpp"
grep -Fq 'ft64_diag_video_opcode' "$SCUMMVM/engines/scumm/script_v6.cpp"
grep -Fq 'vm.slot[_currentScript].number' "$SCUMMVM/engines/scumm/script_v6.cpp"
grep -Fq '#ifndef N64_FT_ONLY' "$SCUMMVM/base/main.cpp"
[ "$(grep -Fc '_player->setCurVideoFlags(_smush_setupsan2);' "$SCUMMVM/engines/scumm/insane/insane.cpp")" -eq 3 ]
# Keep the established 1.6.0 INSANE field rather than importing the later
# source-layout rename from 2023.
grep -Fq 'int16 _smush_setupsan2;' "$SCUMMVM/engines/scumm/insane/insane.h"
# The N64 adaptation deliberately does not allocate the whole AHDR chunk.
if grep -Fq 'byte *headerContent = (byte *)malloc(subSize' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"; then
    echo "unexpected whole-AHDR allocation in r2v SMUSH backport" >&2
    exit 1
fi

for rel in \
    base/main.cpp \
    gui/module.mk \
    engines/scumm/detection.cpp \
    engines/scumm/scumm.cpp \
    engines/scumm/resource.cpp \
    engines/scumm/script_v6.cpp \
    engines/scumm/insane/insane.cpp \
    engines/scumm/smush/smush_player.cpp \
    engines/scumm/smush/smush_player.h; do
    mkdir -p "$ART/patched-source/$(dirname "$rel")"
    cp "$SCUMMVM/$rel" "$ART/patched-source/$rel"
done
sed -n '205,255p;895,970p;1010,1055p;1150,1295p' "$SCUMMVM/engines/scumm/smush/smush_player.cpp" > "$ART/smush-player-after.txt"
grep -n 'FT64DIAG r2v' "$SCUMMVM/engines/scumm/smush/smush_player.cpp" > "$ART/smush-runtime-diagnostic-markers.txt"
sed -n '30,120p' "$SCUMMVM/engines/scumm/smush/smush_player.h" > "$ART/smush-header-after.txt"
sed -n '850,885p;1398,1470p' "$SCUMMVM/engines/scumm/insane/insane.cpp" > "$ART/insane-after.txt"

sed -n '1,125p;330,475p' "$SCUMMVM/base/main.cpp" > "$ART/base-main-after.txt"
sed -n '1025,1125p' "$SCUMMVM/engines/scumm/detection.cpp" > "$ART/scumm-detection-after.txt"
sed -n '95,145p;600,625p;1125,1185p;1260,1420p;1605,1810p;1848,1878p' "$SCUMMVM/engines/scumm/scumm.cpp" > "$ART/scumm-core-after.txt"
sed -n '20,65p;748,825p;965,1055p' "$SCUMMVM/engines/scumm/resource.cpp" > "$ART/scumm-resource-after.txt"
sed -n '20,60p;2378,2445p' "$SCUMMVM/engines/scumm/script_v6.cpp" > "$ART/scumm-video-opcode-after.txt"
grep -n 'FT64 r2v structural: resource' "$SCUMMVM/engines/scumm/resource.cpp" > "$ART/resource-diagnostic-markers.txt"
grep -n 'FT64 r2v structural: .*opcode diagnostic' "$SCUMMVM/engines/scumm/script_v6.cpp" > "$ART/video-opcode-diagnostic-markers.txt"

# Install the hardware-proven libdragon backend as complete source files.
rm -rf "$DST"
mkdir -p "$DST"
cp "$SRC/osys_n64_libdragon.h" "$DST/"
cp "$SRC/osys_n64_libdragon.cpp" "$DST/"
cp "$SRC/nintendo64_libdragon.cpp" "$DST/"
cp "$SRC/n64libdragon-fs.h" "$DST/"
cp "$SRC/n64libdragon-fs.cpp" "$DST/"
cp "$SRC/Makefile.libdragon" "$DST/Makefile"

# Preserve and prove the sparse runtime diagnostics that will be exercised on hardware.
cp "$DST/osys_n64_libdragon.cpp" "$ART/backend-osys-r2v.cpp"
cp "$DST/n64libdragon-fs.cpp" "$ART/backend-fs-r2v.cpp"
grep -n 'FT64DIAG r2v' "$DST/osys_n64_libdragon.cpp" "$DST/n64libdragon-fs.cpp"     > "$ART/backend-runtime-diagnostic-markers.txt"
grep -Fq '[FT64DIAG r2v] HB src=poll' "$DST/osys_n64_libdragon.cpp"
grep -Fq '[FT64DIAG r2v] NEW seq=%u phase=%s kind=%s size=%u' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'caller=%p heap=%d/%d free=%d' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'static const size_t kFt64DiagLargeAllocation = 16384;' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'void ft64_diag_heap_marker(const char *tag)' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'void ft64_diag_resource_event(const char *phase' "$DST/osys_n64_libdragon.cpp"
grep -Fq '[FT64DIAG r2v] RES phase=%s type=%s typeId=%d id=%d' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'contiguous=%d probe=%p heap=%d/%d free=%d' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'void ft64_diag_video_opcode(const char *fileName' "$DST/osys_n64_libdragon.cpp"
grep -Fq '[FT64DIAG r2v] VIDEO opcode=c9 sub=6 file=%s script=%d' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'ft64_diag_heap_marker("ctor-display");' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'DEPTH_16_BPP, 2, GAMMA_NONE' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'ft64_diag_heap_marker("initBackend-mixer");' "$DST/osys_n64_libdragon.cpp"
grep -Fq '__builtin_return_address(0)' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'void *operator new[](size_t size)' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'ft64_allocate_or_abort' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'ft64_diag_new(sequence, "failed", kind, size, 0, caller, true);' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'abort();' "$DST/osys_n64_libdragon.cpp"
if grep -Fq 'throw ' "$DST/osys_n64_libdragon.cpp"; then
    echo "allocator diagnostics use exceptions despite -fno-exceptions" >&2
    exit 1
fi
grep -Fq 'sys_get_heap_stats(&heap);' "$DST/osys_n64_libdragon.cpp"
if grep -Fq 'ft64_diag_resource_heap' "$DST/osys_n64_libdragon.cpp"; then
    echo "obsolete resource.cpp telemetry bridge remains" >&2
    exit 1
fi
grep -Fq '[FT64DIAG r2v] FS MISS' "$DST/n64libdragon-fs.cpp"
grep -Fq '[FT64DIAG r2v] FS READ open' "$DST/n64libdragon-fs.cpp"

# Full Throttle / SCUMM v7-v8 evidence gates.
grep -q 'ifdef ENABLE_SCUMM_7_8' "$SCUMMVM/engines/scumm/module.mk"
grep -q 'ENABLE_SCUMM_7_8' "$SCUMMVM/engines/engines.mk"
test -f "$SCUMMVM/engines/scumm/scumm.h"
grep -Fq 'INCLUDES += -I. -I$(srcdir) -I$(srcdir)/engines' "$DST/Makefile"
grep -q 'ENABLE_SCUMM_7_8 := $(ENABLED)' "$DST/Makefile"
! grep -qE '^ENABLE_AGI[[:space:]]*[:?+]?=' "$DST/Makefile"
! grep -R -n 'backends/fs/posix\|<dirent.h>' "$DST"
grep -q '#include <dir.h>' "$DST/n64libdragon-fs.cpp"
grep -q 'dir_findfirst' "$DST/n64libdragon-fs.cpp"

# Prove the generated make graph contains the expected stripped GUI and FT
# engine objects before spending CI time compiling them.
if [ "${FT64_SKIP_MAKE_DB:-0}" = "1" ]; then
    echo "[integrate] skipping libdragon make-database audit for source-only prepush validation"
else
make -C "$DST" -pn > "$ART/scummvm-make-database.txt" 2> "$ART/scummvm-make-database.stderr"
gui_rule="$(awk '/^gui\/libgui\.a:/ { print; exit }' "$ART/scummvm-make-database.txt")"
if [ -z "$gui_rule" ]; then
    echo "could not find gui/libgui.a in generated make database" >&2
    exit 1
fi
printf '%s\n' "$gui_rule" > "$ART/gui-libgui-rule.txt"
if [[ "$gui_rule" == *"gui/predictivedialog.o"* ]]; then
    echo "predictivedialog.o is still a gui/libgui.a prerequisite" >&2
    exit 1
fi

scumm_rule="$(awk '/^engines\/scumm\/libscumm\.a:/ { print; exit }' "$ART/scummvm-make-database.txt")"
if [ -z "$scumm_rule" ]; then
    echo "could not find engines/scumm/libscumm.a in generated make database" >&2
    exit 1
fi
printf '%s\n' "$scumm_rule" > "$ART/scumm-lib-rule.txt"
for required in \
    engines/scumm/insane/insane.o \
    engines/scumm/resource.o \
    engines/scumm/smush/smush_player.o \
    engines/scumm/imuse_digi/dimuse.o; do
    if [[ "$scumm_rule" != *"$required"* ]]; then
        echo "Full Throttle required object missing from SCUMM module: $required" >&2
        exit 1
    fi
done
fi

git -C "$SCUMMVM" add -N backends/platform/n64libdragon
git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ART/r2v-source-delta.patch"
git -C "$SCUMMVM" status --short > "$ART/scummvm-status-after-integration.txt"

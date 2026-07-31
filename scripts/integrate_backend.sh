#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
SRC="$ROOT/backend"
DST="$SCUMMVM/backends/platform/n64libdragon"
PATCH="$ROOT/upstream/scummvm-1.6.0-ft64.patch"
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
    gui/module.mk \
    engines/scumm/insane/insane.cpp \
    engines/scumm/smush/smush_player.cpp \
    engines/scumm/smush/smush_player.h; do
    mkdir -p "$ART/pristine-source/$(dirname "$rel")"
    cp "$SCUMMVM/$rel" "$ART/pristine-source/$rel"
done

# Focused source neighborhoods make a failed CI run useful instead of opaque.
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

# r2u keeps the verified timing and SMUSH-exit diagnostics in one four-file
# ScummVM patch. Heap diagnostics live at the backend allocation boundary,
# with no regex rewrite, sed mutation, secondary patch, or fuzzy fallback.
echo "[integrate] checking consolidated r2u timing+diagnostic patch against pinned ScummVM"
git -C "$SCUMMVM" apply --check "$PATCH"
echo "[integrate] applying consolidated r2u timing+diagnostic patch once"
git -C "$SCUMMVM" apply "$PATCH"

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
grep -Fq '[FT64DIAG r2u] SMUSH begin' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2u] SMUSH eof' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2u] SMUSH loop-exit' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '[FT64DIAG r2u] SMUSH released' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'extern void ft64_diag_heap_marker(const char *tag);' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-begin");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-before-release");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq '::ft64_diag_heap_marker("smush-after-release");' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
[ "$(grep -Fc '_player->setCurVideoFlags(_smush_setupsan2);' "$SCUMMVM/engines/scumm/insane/insane.cpp")" -eq 3 ]
# Keep the established 1.6.0 INSANE field rather than importing the later
# source-layout rename from 2023.
grep -Fq 'int16 _smush_setupsan2;' "$SCUMMVM/engines/scumm/insane/insane.h"
# The N64 adaptation deliberately does not allocate the whole AHDR chunk.
if grep -Fq 'byte *headerContent = (byte *)malloc(subSize' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"; then
    echo "unexpected whole-AHDR allocation in r2u SMUSH backport" >&2
    exit 1
fi

for rel in \
    gui/module.mk \
    engines/scumm/insane/insane.cpp \
    engines/scumm/smush/smush_player.cpp \
    engines/scumm/smush/smush_player.h; do
    mkdir -p "$ART/patched-source/$(dirname "$rel")"
    cp "$SCUMMVM/$rel" "$ART/patched-source/$rel"
done
sed -n '205,255p;895,970p;1010,1055p;1150,1295p' "$SCUMMVM/engines/scumm/smush/smush_player.cpp" > "$ART/smush-player-after.txt"
grep -n 'FT64DIAG r2u' "$SCUMMVM/engines/scumm/smush/smush_player.cpp" > "$ART/smush-runtime-diagnostic-markers.txt"
sed -n '30,120p' "$SCUMMVM/engines/scumm/smush/smush_player.h" > "$ART/smush-header-after.txt"
sed -n '850,885p;1398,1470p' "$SCUMMVM/engines/scumm/insane/insane.cpp" > "$ART/insane-after.txt"

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
cp "$DST/osys_n64_libdragon.cpp" "$ART/backend-osys-r2u.cpp"
cp "$DST/n64libdragon-fs.cpp" "$ART/backend-fs-r2u.cpp"
grep -n 'FT64DIAG r2u' "$DST/osys_n64_libdragon.cpp" "$DST/n64libdragon-fs.cpp"     > "$ART/backend-runtime-diagnostic-markers.txt"
grep -Fq '[FT64DIAG r2u] HB src=poll' "$DST/osys_n64_libdragon.cpp"
grep -Fq '[FT64DIAG r2u] NEW seq=%u phase=%s kind=%s size=%u' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'caller=%p heap=%d/%d free=%d' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'static const size_t kFt64DiagLargeAllocation = 16384;' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'void ft64_diag_heap_marker(const char *tag)' "$DST/osys_n64_libdragon.cpp"
grep -Fq 'ft64_diag_heap_marker("ctor-display");' "$DST/osys_n64_libdragon.cpp"
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
grep -Fq '[FT64DIAG r2u] FS MISS' "$DST/n64libdragon-fs.cpp"
grep -Fq '[FT64DIAG r2u] FS READ open' "$DST/n64libdragon-fs.cpp"

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

git -C "$SCUMMVM" add -N backends/platform/n64libdragon
git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ART/r2u-source-delta.patch"
git -C "$SCUMMVM" status --short > "$ART/scummvm-status-after-integration.txt"

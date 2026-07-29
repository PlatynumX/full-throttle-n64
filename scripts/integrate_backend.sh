#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
SRC="$ROOT/backend"
DST="$SCUMMVM/backends/platform/n64libdragon"
PATCH="$ROOT/upstream/scummvm-1.6.0-ft64.patch"
ART="$ROOT/artifacts"
PINNED_SCUMMVM="f75a652bb7c956f145abe881c87b5dbf5c9ec24b"

mkdir -p "$ART"
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

capture_context() {
  local rel="$1"
  local pattern="$2"
  local out="$3"
  if ! grep -n -B8 -A35 -- "$pattern" "$SCUMMVM/$rel" > "$ART/$out"; then
    echo "expected pristine-source anchor not found: $rel :: $pattern" >&2
    exit 1
  fi
}

# Preserve the exact pinned-source neighborhoods that the one consolidated
# upstream patch is expected to touch. If the patch ever stops applying, the
# build artifact therefore contains evidence from the pristine tree rather than
# requiring a speculative follow-up.
capture_context gui/module.mk 'predictivedialog\.o' gui-module-before.txt
capture_context engines/scumm/smush/smush_player.cpp 'SmushPlayer::handleAnimHeader' smush-header-before.txt
capture_context engines/scumm/smush/smush_player.h 'getVideoPalette' smush-player-header-before.txt
capture_context engines/scumm/insane/insane.cpp 'smush_rewindCurrentSan' insane-flags-before.txt
capture_context engines/scumm/insane/insane.cpp 'smush_setupSanWithFlu' insane-setup-before.txt
capture_context engines/scumm/scumm.cpp '_smushFrameRate' scumm-framerate-before.txt

if [ "$(grep -c '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk")" -ne 1 ]; then
  echo "expected exactly one predictivedialog.o entry in pristine gui/module.mk" >&2
  exit 1
fi

# One patch, one application, against the exact pristine pinned tree. There is
# deliberately no fuzzy/sed/regex fallback. The later SMUSH logic comes from
# ScummVM upstream commit 9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8.
echo "[integrate] checking consolidated source patch against pinned ScummVM"
git -C "$SCUMMVM" apply --check "$PATCH"
echo "[integrate] applying consolidated source patch once"
git -C "$SCUMMVM" apply "$PATCH"

# Verify the intended source-level results, not merely a zero exit code.
if grep -q '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk"; then
  echo "predictivedialog.o remained in GUI module after patch" >&2
  exit 1
fi
grep -Fq 'video speed override' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'setCurVideoFlags' "$SCUMMVM/engines/scumm/smush/smush_player.cpp"
grep -Fq 'setCurVideoFlags' "$SCUMMVM/engines/scumm/smush/smush_player.h"
grep -Fq '_curVideoFlags' "$SCUMMVM/engines/scumm/smush/smush_player.h"
grep -Fq '_smush_curSanFlags' "$SCUMMVM/engines/scumm/insane/insane.cpp"
grep -Fq 'syncCurrentSanFlags' "$SCUMMVM/engines/scumm/insane/insane.cpp"
grep -Fq 'syncCurrentSanFlags' "$SCUMMVM/engines/scumm/insane/insane.h"

capture_context gui/module.mk 'options\.o' gui-module-after.txt
capture_context engines/scumm/smush/smush_player.cpp 'SmushPlayer::handleAnimHeader' smush-header-after.txt
capture_context engines/scumm/smush/smush_player.h 'setCurVideoFlags' smush-player-header-after.txt
capture_context engines/scumm/insane/insane.cpp 'syncCurrentSanFlags' insane-flags-after.txt

rm -rf "$DST"
mkdir -p "$DST"
cp "$SRC/osys_n64_libdragon.h" "$DST/"
cp "$SRC/osys_n64_libdragon.cpp" "$DST/"
cp "$SRC/nintendo64_libdragon.cpp" "$DST/"
cp "$SRC/n64libdragon-fs.h" "$DST/"
cp "$SRC/n64libdragon-fs.cpp" "$DST/"
cp "$SRC/Makefile.libdragon" "$DST/Makefile"

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

# Make's module rules archive GUI objects into gui/libgui.a. Prove the actual
# graph no longer contains predictivedialog.o before starting compilation.
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
  engines/scumm/smush/smush_player.o \
  engines/scumm/imuse_digi/dimuse.o; do
  if [[ "$scumm_rule" != *"$required"* ]]; then
    echo "Full Throttle required object missing from SCUMM module: $required" >&2
    exit 1
  fi
done

# The real V=1 cross-build is authoritative for compiler/linker/package command
# behavior. Do not gate it with a brittle parser of make -n output.

git -C "$SCUMMVM" add -N backends/platform/n64libdragon
git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ART/r2n-source-delta.patch"
git -C "$SCUMMVM" status --short > "$ART/scummvm-status-after-integration.txt"

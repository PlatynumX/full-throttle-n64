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

# Record the exact upstream GUI module stanza before touching it.
grep -n -B2 -A2 'predictivedialog\.o' "$SCUMMVM/gui/module.mk" \
  > "$ART/gui-module-before.txt"
if [ "$(grep -c '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk")" -ne 1 ]; then
  echo "expected exactly one predictivedialog.o entry in pristine gui/module.mk" >&2
  exit 1
fi

# One proper patch, always against the pristine pinned tree. No sed/regex mutation
# chain and no patch-on-patch behavior.
git -C "$SCUMMVM" apply --check "$PATCH"
git -C "$SCUMMVM" apply "$PATCH"

if grep -q '^[[:space:]]*predictivedialog\.o[[:space:]]*\\' "$SCUMMVM/gui/module.mk"; then
  echo "predictivedialog.o remained in GUI module after patch" >&2
  exit 1
fi
grep -n -B2 -A2 'options\.o\|saveload\.o' "$SCUMMVM/gui/module.mk" \
  > "$ART/gui-module-after.txt"

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
make -C "$DST" -pn > "$ART/scummvm-make-database.txt"
gui_rule="$(grep '^gui/libgui\.a:' "$ART/scummvm-make-database.txt" | head -1 || true)"
if [ -z "$gui_rule" ]; then
  echo "could not find gui/libgui.a in generated make database" >&2
  exit 1
fi
printf '%s\n' "$gui_rule" > "$ART/gui-libgui-rule.txt"
if printf '%s\n' "$gui_rule" | grep -q 'gui/predictivedialog\.o'; then
  echo "predictivedialog.o is still a gui/libgui.a prerequisite" >&2
  exit 1
fi

scumm_rule="$(grep '^engines/scumm/libscumm\.a:' "$ART/scummvm-make-database.txt" | head -1 || true)"
if [ -z "$scumm_rule" ]; then
  echo "could not find engines/scumm/libscumm.a in generated make database" >&2
  exit 1
fi
printf '%s\n' "$scumm_rule" > "$ART/scumm-lib-rule.txt"
for required in \
  engines/scumm/insane/insane.o \
  engines/scumm/smush/smush_player.o \
  engines/scumm/imuse_digi/dimuse.o; do
  if ! printf '%s\n' "$scumm_rule" | grep -Fq "$required"; then
    echo "Full Throttle required object missing from SCUMM module: $required" >&2
    exit 1
  fi
done

# Capture the complete clean delta against the pinned source.
git -C "$SCUMMVM" add -N backends/platform/n64libdragon
git -C "$SCUMMVM" diff --check
git -C "$SCUMMVM" diff > "$ART/r2g-source-delta.patch"
git -C "$SCUMMVM" status --short > "$ART/scummvm-status-after-integration.txt"

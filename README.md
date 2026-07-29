# Full Throttle N64 r2o

Full Throttle-only ScummVM 1.6.0 port for Nintendo 64, using libdragon and
SummerCart SD storage.

## Hardware baseline

r2m builds and runs on a real N64 with an Expansion Pak. Full Throttle launches
from `sd:/fullthrottle/`, the opening SMUSH movie plays, and gameplay is reached.
The latest hardware test reports two remaining runtime problems:

1. SMUSH video is still choppy;
2. leaving the initial gameplay screen can transition to a black screen.

r2o changes only those two areas. Controls, SD filesystem behavior, save paths,
audio configuration, and the r2m preconverted game framebuffer remain otherwise
unchanged.

## Black-screen transition fix

ScummVM's overlay contract says `clearOverlay()` must leave the game graphics
visible while overlay mode is active. A backend without real alpha blending is
expected to achieve that by copying the current game image into its overlay.
The historical ScummVM N64 backend does exactly that.

r2m instead zeroed the entire overlay buffer, producing a black overlay.

r2o therefore:

- rebuilds the converted game frame when necessary;
- clears only the unused overlay area;
- copies the current game frame into the overlay in ScummVM's N64 RGB555 layout;
- marks the display dirty;
- immediately presents the game frame when `hideOverlay()` is called, matching
  the historical N64 backend's explicit protection for games that do not issue
  another screen update when leaving an overlay;
- emits USB/emulator debug messages for `showOverlay`, `clearOverlay`, and
  `hideOverlay` so a remaining transition failure can be tied to the exact
  runtime path instead of guessed at.

## SMUSH timing backport

ScummVM upstream commit:

```text
9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8
SCUMM: INSANE/SMUSH: Implement video file dependent frame rate
```

states that Full Throttle video files contain their correct frame rate in the
FLU header and that using it fixes ScummVM bug #14029. ScummVM 2.7.0 release
notes subsequently describe SMUSH timing fixes mostly affecting Full Throttle.

The r2n failure exposed that the 2023 header hunk did not match ScummVM 1.6.0.
r2o was rebuilt after inspecting the exact pinned 1.6.0 SMUSH and INSANE source.
It adapts the upstream behavior to that verified class layout instead of copying
a newer-source hunk. The already-required `gui/predictivedialog.o` removal and
the adapted SMUSH changes remain **one consolidated Git patch**. There is no
second patcher and no sed/regex fallback.

GitHub CI still enforces exact compatibility before compilation:

```text
git apply --check
```

against exactly:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

If any source context differs, integration stops before the compiler runs. The
artifact preserves complete pristine copies of every file touched by the patch
plus `integration.log`. There is deliberately no fuzzy fallback.

## Game data

No Full Throttle game or demo data is downloaded, embedded, staged, or uploaded
by this repository.

The ROM expects the existing game data at:

```text
sd:/fullthrottle/
```

and saves at:

```text
sd:/fullthrottle/saves/
```

## Build output

GitHub Actions builds:

```text
ft64-sd-probe.z64
full-throttle-n64-r2o.z64
```

The build artifact contains ROMs and diagnostics only.

See `TERMUX.md` for the Android publish commands and `docs/EVIDENCE.md` for the
source evidence behind the two r2o changes.

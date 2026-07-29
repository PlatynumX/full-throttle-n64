# r2o architecture

## Runtime data path

```text
SummerCart SD
  sd:/fullthrottle/
          |
          v
libdragon FAT / stdio
          |
          v
ScummVM 1.6.0 SCUMM v7
          |
          v
Full Throttle
```

No game-data payload is part of CI or the build artifact.

## Video presentation

ScummVM renders its normal 8-bit CLUT game surface. The N64 backend retains the
r2m second 16-bit converted surface, so ordinary presentation is bulk copy
rather than a full palette conversion in every `updateScreen()`.

r2o additionally fixes fake-alpha overlay handling: `clearOverlay()` composes
the current game frame into the overlay instead of leaving it black, and
`hideOverlay()` immediately presents the game frame so an overlay transition
does not depend on a later engine-driven redraw.

## SMUSH timing

The SCUMM v7 engine starts from pinned ScummVM 1.6.0. A single consolidated
source patch adds the later upstream Full Throttle file-dependent SMUSH
frame-rate logic and removes the unused predictive-input GUI object required by
this stripped build.

The patch is applied once, only after `git apply --check` succeeds against the
exact pinned checkout. No fallback source mutation exists.

## Input

r2o retains the r2m libdragon Joypad/mouse path unchanged. Controls are not part
of this runtime pass.

## Audio/timers

r2o does not change r2m audio configuration or timer servicing. Audio remains
22050 Hz with three libdragon buffers. The ScummVM timer manager remains serviced
from normal backend execution rather than interrupt context.

## Source policy

Every CI build fetches the pinned ScummVM source and pinned libdragon revision
from scratch. Platform changes live as clean backend files. The only ScummVM
source mutation is the single checked Git patch in `upstream/`.

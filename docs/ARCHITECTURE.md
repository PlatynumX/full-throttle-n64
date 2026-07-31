# r2s architecture

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
r2m second 16-bit converted surface, so ordinary presentation is a bulk copy
rather than a palette conversion for every pixel on every presentation.

The existing overlay transition correction is retained: `clearOverlay()`
composes the current game frame into the fake-alpha overlay, and `hideOverlay()`
immediately presents the game frame.

## SMUSH timing

The SCUMM v7 engine starts from pinned ScummVM 1.6.0. One consolidated source
patch makes the smallest Full-Throttle-specific backport of upstream commit
`9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8` that fits the verified 1.6.0 class
layout.

The backport reads the version and frame rate directly from the AHDR stream,
tracks the existing INSANE SAN flags, and does not allocate a copy of the entire
header. `git apply --check` must succeed against the exact pinned checkout before
the patch is applied once.

## Input

r2s retains the r2m libdragon Joypad/mouse path unchanged.

## Audio/timers

r2s does not change the established audio configuration or timer servicing.
Audio remains 22050 Hz with three libdragon buffers. The ScummVM timer manager is
serviced from normal backend execution rather than interrupt context.

## Source policy

Every CI build fetches the pinned ScummVM source and pinned libdragon revision
from scratch. Platform code is installed as complete backend files. The only
ScummVM source mutation is `upstream/scummvm-1.6.0-ft64.patch`, applied once
after an exact `git apply --check`. No fallback rewrite exists.


## r2s diagnostic layer

r2s does not change the architecture of the renderer or filesystem. It adds
observation points only: SMUSH lifecycle markers in the pinned engine patch,
bounded filesystem logging, overlay markers, and a one-second backend heartbeat.
The heartbeat is emitted from either updateScreen() or pollEvent(), whichever
reaches the one-second threshold first, so a black screen can be distinguished
from a dead main loop.

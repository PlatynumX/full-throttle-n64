# r2m architecture

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

## Video

ScummVM renders its normal 8-bit CLUT game surface. The N64 backend maintains a
second 16-bit converted surface. Rectangle updates update both surfaces while
the palette is stable; palette changes and direct surface writes mark the
converted surface for rebuild. `updateScreen()` copies the 16-bit surface to a
libdragon display buffer and draws the cursor.

This follows the two-buffer design used by the historical official ScummVM N64
backend while retaining libdragon display ownership.

## Input

libdragon reads Joybus devices asynchronously during VI. The backend
synchronizes a cached controller state at a bounded frame cadence, applies the
historical N64 analog-to-pointer curve to floating-point accumulated
coordinates, and emits pointer motion every 40 ms.

Digital button edges are derived from current versus retained button state,
rather than consuming libdragon transition helpers on every ScummVM event
poll.

## Audio/timers

r2m does not change r2l audio configuration or timer servicing. Audio remains
22050 Hz with three libdragon buffers. The ScummVM timer manager continues to
be serviced from normal backend execution rather than interrupt context.

## Source policy

ScummVM is reset to the pinned v1.6.0 commit on every build. The only upstream
source patch is the existing one-file removal of unused AGI predictive-dialog
code from `gui/module.mk`. The r2m runtime work lives directly in the
`n64libdragon` backend source, not in a new mutation script or stacked patch.

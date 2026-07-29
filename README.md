# Full Throttle N64 r2m

Full Throttle-only ScummVM 1.6.0 port for Nintendo 64, using libdragon and
SummerCart SD storage.

## Baseline

r2l built successfully and booted on real N64 hardware with an Expansion Pak.
The SummerCart SD filesystem mounted and Full Throttle reached the opening
SMUSH movie. Hardware testing then exposed two runtime issues:

1. opening movie playback stutters;
2. the analog stick does not behave correctly as the mouse.

r2m changes only the platform backend paths directly related to those two
observations. It does not change the Full Throttle engine, game scripts, audio
buffer count, filesystem implementation, or the existing ScummVM 1.6.0 GUI
module patch.

## r2m input change

The historical official ScummVM N64 backend used the N64 analog stick as mouse
movement. It sampled analog movement at display cadence into floating-point
temporary mouse coordinates and emitted mouse movement at a bounded 40 ms
interval.

r2m follows that established behavior using libdragon's Joypad subsystem:

- libdragon continues reading controllers asynchronously from VI;
- `joypad_poll()` synchronizes state at a bounded frame cadence rather than on
  every ScummVM `pollEvent()` drain;
- analog X/Y is clamped to +/-60;
- the historical tangent acceleration curve is retained;
- accumulated pointer motion is emitted every 40 ms;
- button edges are compared against retained button state, so repeated event
  polling does not consume libdragon pressed/released transitions prematurely.

Controls remain:

- Analog stick: mouse
- Z: left click
- B: right click
- Start: F5 menu
- L: Escape
- A: period / skip

## r2m video change

r2l converted every 8-bit game pixel through the palette again during every
screen presentation.

The historical N64 backend instead kept both the palettized game buffer and a
preconverted 16-bit N64 buffer. `copyRectToScreen()` updated that converted
buffer when pixels changed, palette changes invalidated it, and `updateScreen()`
mostly copied already-converted pixels to the framebuffer.

r2m restores that architecture in the libdragon backend:

- `_game` remains ScummVM's 8-bit CLUT surface;
- `_game16` stores the converted RGBA5551 frame;
- ordinary rectangle updates update the converted pixels once;
- palette/direct-surface changes trigger a rebuild before presentation;
- clean frames are not presented again;
- presentation uses row copies instead of a full-screen per-pixel palette
  conversion.

This is a targeted backend optimization based on the historical N64 port. It is
not yet claimed to eliminate the observed SMUSH stutter; hardware testing is
the authority.

## Game data

No Full Throttle game or demo data is downloaded, embedded, staged, or uploaded
by this repository.

The ROM expects the user's existing files at:

```text
sd:/fullthrottle/
```

The save manager expects this directory to already exist:

```text
sd:/fullthrottle/saves/
```

## Build

GitHub Actions fetches only the pinned source/toolchain dependencies, then builds:

```text
ft64-sd-probe.z64
full-throttle-n64-r2m.z64
```

The build artifact contains ROMs and diagnostics only.

See `TERMUX.md` for the Android/Termux publish command and `docs/EVIDENCE.md`
for the exact upstream behavior used for the r2m changes.

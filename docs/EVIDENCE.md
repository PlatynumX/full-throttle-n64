# Evidence / design notes — r2n

## Hardware observation

The r2m ROM runs on real Nintendo 64 hardware with an Expansion Pak and
SummerCart. Full Throttle loads from `sd:/fullthrottle/`, plays the opening
SMUSH video, and reaches gameplay.

The current hardware observations are:

- SMUSH video remains choppy.
- Transitioning away from the initial gameplay screen can leave a black screen.

Those are the only runtime problems targeted by r2n. Hardware retesting remains
the authority on whether either issue is resolved.

## Overlay contract and historical N64 behavior

ScummVM's OSystem overlay documentation says that after `clearOverlay()` while
overlay mode is active, only the game graphics should be visible. For fake
alpha blending, the documented method is to copy the current game graphics into
the overlay.

Current API documentation:

https://doxygen.scummvm.org/da/da9/group__common__system__overlay.html

The pinned ScummVM 1.6.0 N64 backend implements that behavior directly in
`clearOverlay()` by clearing the overlay buffer and then copying the current
high-color game buffer into it:

https://raw.githubusercontent.com/scummvm/scummvm/v1.6.0/backends/platform/n64/osys_n64_base.cpp

That same historical backend's `hideOverlay()` explicitly forces a screen
presentation because some games may not update the screen themselves when the
overlay is disabled.

r2m violated the first requirement by making `clearOverlay()` a black-buffer
clear only. r2n restores the fake-alpha behavior and performs an immediate game
presentation from `hideOverlay()`.

The r2n game buffer is libdragon RGBA5551. ScummVM 1.6.0's `ColorMasks<555>`
has an N64-specific layout with red at bit 11, green at bit 6, blue at bit 1,
and the low bit unused. Therefore copying the converted game pixel into the
overlay while clearing bit 0 preserves the color bits and yields the format
advertised by `getOverlayFormat()`.

Pinned color-mask source:

https://raw.githubusercontent.com/scummvm/scummvm/v1.6.0/graphics/colormasks.h

## Full Throttle SMUSH frame-rate evidence

ScummVM upstream commit:

```text
9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8
SCUMM: INSANE/SMUSH: Implement video file dependent frame rate
```

was committed on 2023-01-15. Its commit message says:

```text
In FT and DIG demo, video files have the correct frame rate encoded in the FLU header.
This fixes bug #14029.
```

Commit record and diff:

https://lists.scummvm.org/pipermail/scummvm-git-logs/2023-January/097937.html

The upstream change reads the video speed from the AHDR/FLU header for Full
Throttle, tracks the current INSANE/SMUSH video flags, and uses the encoded
speed when the flags permit it.

ScummVM 2.7.0 release notes separately state that minor SMUSH timing issues were
fixed, mostly affecting Full Throttle:

https://docs.scummvm.org/en/v2.7.0/help/release.html

The same release also introduced a low-latency audio mode. r2n does **not**
enable or backport that audio mode: it is a separate behavior and is not needed
to test the identified frame-rate correction.

## Backport verification policy

The exact ScummVM build source remains pinned to:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

The r2n project contains one consolidated source patch covering:

- `gui/module.mk` — the already-established removal of unused
  `predictivedialog.o`;
- the five SCUMM files changed by upstream frame-rate commit
  `9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8`.

The packaging environment could verify the patch format and exact intended path
set, but could not retrieve the pinned source checkout. Therefore compatibility
with ScummVM 1.6.0 is **not asserted locally**.

CI first records relevant pristine source excerpts and then runs exactly one:

```text
git apply --check upstream/scummvm-1.6.0-ft64.patch
git apply upstream/scummvm-1.6.0-ft64.patch
```

If the check fails, there is no automatic rewrite, fuzzy application, sed
mutation, or fallback patch. The build report keeps `integration.log` and the
pristine excerpts so the next source change can be based on the actual pinned
code.

## No game/demo packaging

r2n does not fetch, stage, archive, or upload Full Throttle data. Hardware uses
the existing `sd:/fullthrottle/` directory.

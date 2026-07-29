# Evidence / design notes — r2o

## Hardware baseline

r2m runs on real Nintendo 64 hardware with an Expansion Pak and SummerCart.
Full Throttle loads from `sd:/fullthrottle/`, plays the opening SMUSH video, and
reaches gameplay. r2o retains that controller, filesystem, audio/timer, and
preconverted-framebuffer path.

## Exact pinned source

ScummVM is pinned to:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

libdragon is pinned to:

```text
35f85a0797324a5ed0c723203e33ab3c1da94fdd
```

Inspection of the pinned ScummVM source establishes the actual 1.6.0 layout:

- `engines/scumm/smush/smush_player.h` is 132 lines;
- `_speed` and `_skipPalette` are private fields in the compact 1.6.0 class;
- `handleAnimHeader()` reads a 6-byte prefix followed by the 0x300-byte palette;
- `Insane` stores the SAN flags in `_smush_setupsan2` at rewind, FLU setup, and
  from-start setup sites;
- `ScummEngine_v7::setupScumm()` already gives Full Throttle a 10 fps default.

Those facts are why r2o does not import later `insane.h` renames or the unrelated
DIG-demo `scumm.cpp` change.

## Upstream Full Throttle frame-rate evidence

Upstream ScummVM commit:

```text
9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8
SCUMM: INSANE/SMUSH: Implement video file dependent frame rate
```

states that Full Throttle video files contain their correct frame rate in the
FLU/AHDR data. Its implementation reads the speed at `6 + 0x300`, uses it for
header versions greater than 1, and suppresses the override when SAN flag bit 3
is set.

r2o preserves that behavior but adapts it to the pinned 1.6.0 source instead of
copying 2023 hunk contexts. To reduce transient RAM use on N64, r2o reads the
needed fields directly from the existing seekable stream rather than allocating
a buffer for the entire AHDR chunk.

Upstream commit record:
https://github.com/scummvm/scummvm/commit/9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8

## Overlay evidence

The retained backend implements ScummVM's fake-alpha overlay contract by copying
the current converted game frame into the overlay in `clearOverlay()` and by
presenting immediately in `hideOverlay()`. r2o deliberately does not touch that
backend logic while correcting the ScummVM source patch.

## Backport verification policy

The r2o project has exactly one ScummVM patch, touching only:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

CI records pristine source neighborhoods and then runs exactly one check and one
application:

```text
git apply --check upstream/scummvm-1.6.0-ft64.patch
git apply upstream/scummvm-1.6.0-ft64.patch
```

Afterward it verifies the expected symbols and all three SAN-flag synchronization
sites, checks the generated Make database for the stripped GUI and required Full
Throttle engine objects, and runs `git diff --check`.

There is no `--3way`, fuzzy patching, sed/regex mutation, or second source patch.

## No game/demo packaging

r2o does not fetch, stage, archive, or upload Full Throttle game/demo data.
Hardware uses the existing `sd:/fullthrottle/` directory.

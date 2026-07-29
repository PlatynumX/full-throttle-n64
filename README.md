# Full Throttle N64 r2q

Full Throttle-only ScummVM 1.6.0 port for Nintendo 64, using libdragon and
SummerCart SD storage.

## Hardware baseline

r2m builds and runs on real N64 hardware with an Expansion Pak. Full Throttle
launches from `sd:/fullthrottle/`, the opening SMUSH movie plays, and gameplay is
reached. The hardware-proven r2m controller path, SD/save path, audio setup,
preconverted 16-bit presentation path, and later overlay transition correction
are retained.

The active runtime target remains smoother/correct SMUSH timing.

## What the r2o CI report proved

The r2o integration gate correctly stopped before compilation because its
consolidated patch did not apply exactly to pinned ScummVM:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

The pristine files preserved by that run show that three r2o hunks omitted blank
lines present in the exact 1.6.0 source:

- after `_smush_setupsan2 = setupsan2;` in `smush_setupSanWithFlu()`;
- after the AHDR size assertion in `handleAnimHeader()`;
- between `_skipPalette` and `public:` in `SmushPlayer`.

`git apply --check --verbose` reproduces those exact context failures. This was
a patch-construction error, not a different pinned revision and not a compiler
failure.

## r2q correction

r2q discards the failed r2o patch and regenerates the one consolidated Git patch
from the exact pristine source files preserved by that CI run.

The Full Throttle timing behavior remains adapted from upstream ScummVM commit:

```text
9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8
SCUMM: INSANE/SMUSH: Implement video file dependent frame rate
```

For Full Throttle, r2q:

- synchronizes the current INSANE SAN flags at the three verified 1.6.0
  assignment sites;
- reads AHDR major/minor version directly from the existing stream;
- reads the encoded frame rate after the six-byte prefix and 0x300-byte palette;
- applies a non-zero encoded rate for header versions greater than 1 when SAN
  flag bit 3 is clear;
- preserves `_skipPalette` behavior while still advancing to the rate field;
- avoids the later upstream whole-AHDR allocation;
- leaves `insane.h` and `scumm.cpp` untouched because their later-source changes
  are unnecessary for this Full-Throttle-only build.

The existing `gui/predictivedialog.o` removal remains in that same patch.

## Verification

The update bundle contains the four exact pristine files preserved by r2o CI and
runs `git apply --check`, applies the patch once, and runs `git diff --check`
against them locally before it is allowed to push r2q.

GitHub CI independently fetches pinned ScummVM from scratch and repeats the exact
patch check/application before any N64 compilation. It then verifies patched
source, the generated Make database, required Full Throttle objects, and
`git diff --check`.

There is no `--3way`, fuzzy application, sed/regex source mutation, or patch
stack.

## Game data

No Full Throttle game/demo data is downloaded, embedded, staged, or uploaded.
The ROM expects existing data at `sd:/fullthrottle/` and saves at
`sd:/fullthrottle/saves/`.

## Build output

```text
ft64-sd-probe-r2q.z64
full-throttle-n64-r2q.z64
```

Build artifact: `full-throttle-n64-r2q-build-report`.

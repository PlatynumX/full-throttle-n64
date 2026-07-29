# Full Throttle N64 r2o

Full Throttle-only ScummVM 1.6.0 port for Nintendo 64, using libdragon and
SummerCart SD storage.

## Hardware baseline

r2m builds and runs on real N64 hardware with an Expansion Pak. Full Throttle
launches from `sd:/fullthrottle/`, the opening SMUSH movie plays, and gameplay is
reached. The r2m controller path and preconverted 16-bit presentation path are
retained.

The next observed runtime targets were choppy SMUSH playback and a black
transition when leaving the initial gameplay screen. The overlay transition
correction already present in the current backend is retained unchanged in r2o.

## Why r2o replaces the r2n source patch

The r2n SMUSH patch copied 2023 ScummVM source hunks whose class layout no longer
matched the pinned 2013 ScummVM checkout. In particular, pinned
`smush_player.h` is only 132 lines and does not contain the later public methods
used as r2n hunk context. r2o does not add another patch on top.

Instead, r2o replaces the consolidated patch with a minimal backport written
against the verified pinned layout:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

The behavior comes from upstream ScummVM commit:

```text
9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8
SCUMM: INSANE/SMUSH: Implement video file dependent frame rate
```

For Full Throttle, r2o:

- tracks the current INSANE SAN flags at the three existing 1.6.0 assignment
  sites;
- reads AHDR major/minor version and the encoded frame rate at offset
  `6 + 0x300`;
- applies the encoded non-zero rate when flag bit 3 is clear;
- preserves palette handling when `_skipPalette` is active;
- avoids the later upstream whole-header `malloc`, reading directly from the
  existing stream instead, which is preferable on an 8 MiB N64 target;
- leaves `insane.h` and `scumm.cpp` untouched because their later-source changes
  are not needed for this Full-Throttle-only build.

The already-required `gui/predictivedialog.o` removal is in the same single Git
patch. There is no fuzzy application, sed rewrite, second patcher, or fallback.

## Verification

CI fetches the exact pinned ScummVM checkout from scratch and runs:

```text
git apply --check upstream/scummvm-1.6.0-ft64.patch
git apply upstream/scummvm-1.6.0-ft64.patch
```

exactly once. It then checks the resulting source, generated Make database,
required Full Throttle objects, and `git diff --check` before compilation.
Pristine and patched source neighborhoods are kept in the build-report artifact.

## Game data

No Full Throttle game or demo data is downloaded, embedded, staged, or uploaded
by this repository. The ROM expects existing data at:

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
ft64-sd-probe-r2o.z64
full-throttle-n64-r2o.z64
```

The artifact is named `full-throttle-n64-r2o-build-report` and contains ROMs and
diagnostics only.

See `TERMUX.md` for Android publishing commands and `docs/EVIDENCE.md` for the
source evidence behind the backport.

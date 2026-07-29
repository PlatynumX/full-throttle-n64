# Full Throttle N64 r2g

Full Throttle-only ScummVM 1.6.0 bring-up for Nintendo 64 using libdragon and SummerCart SD storage.

## Current target

```text
Nintendo 64 + Expansion Pak
        |
        +-- libdragon backend
        +-- ScummVM 1.6.0 SCUMM engine
        +-- SCUMM v7/v8
        +-- SMUSH + INSANE + iMUSE Digital
        +-- sd:/fullthrottle/ game data
        +-- sd:/fullthrottle/saves/ save data
```

The repository does not contain the retail game. CI fetches ScummVM's public DOS Full Throttle demo and stages it as the hardware test payload.

## Why r2g exists

The r2f CI build reached `gui/predictivedialog.cpp` and failed on legacy predictive-input code. The attempted r2f Makefile filter was ineffective.

The reason is now verified in ScummVM 1.6.0's build system: `Makefile.common` includes each module's `module.mk`, and `rules.mk` turns static modules into archives such as `gui/libgui.a`. `gui/predictivedialog.o` is therefore a prerequisite of `gui/libgui.a`, not a top-level `OBJS` entry. Filtering top-level `OBJS` after `Makefile.common` cannot remove it.

r2g discards that approach completely.

## Clean source policy

Every CI run starts from pristine pinned ScummVM 1.6.0 commit:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

and pinned libdragon commit:

```text
35f85a0797324a5ed0c723203e33ab3c1da94fdd
```

There is no revision-to-revision patch chain. The platform backend is stored as complete source files in `backend/`.

One normal Git patch, `upstream/scummvm-1.6.0-ft64.patch`, is applied directly to the pristine pinned ScummVM tree. Its only purpose is to remove the unrelated AGI predictive-input object from `gui/module.mk` before ScummVM constructs the GUI archive dependency graph.

Before compilation, CI uses GNU make's generated database to prove:

* `gui/libgui.a` does **not** depend on `gui/predictivedialog.o`;
* `engines/scumm/libscumm.a` still includes Full Throttle's INSANE, SMUSH, and iMUSE Digital objects.

If either check fails, compilation does not start.

## Backend

The new backend uses:

* libdragon 320x240 video;
* libdragon audio buffers;
* libdragon joypad input;
* a native ScummVM filesystem adapter backed by libdragon `dir_t`, `dir_findfirst()` and `dir_findnext()`;
* standard file streams over the mounted `sd:/` filesystem;
* SD saves through `DefaultSaveFileManager("sd:/fullthrottle/saves")`;
* libdragon USB/emulator debug output.

The old hkz-libn64, ROMFS, PakFS and FRAMFS backend is not used.

## Build outputs

The GitHub Action uploads `full-throttle-n64-r2g-build-report` containing diagnostics plus, when successful:

```text
ft64-sd-probe.z64
full-throttle-n64-r2g.z64
sdcard/fullthrottle/
```

The standalone probe isolates libdragon/SummerCart display, audio, input and SD access from ScummVM itself.

## SD layout

Copy the staged payload so the card contains:

```text
sd:/fullthrottle/
    <Full Throttle demo or retail data>
    saves/
```

The application launches ScummVM as:

```text
-p sd:/fullthrottle ft
```

## Current controller mapping

```text
Analog stick  mouse pointer
Z             left click
B             right click
Start         F5 / ScummVM menu
L             Escape
A             period key (temporary historical mapping)
```

## Local validation

```bash
bash ./scripts/preflight.sh
```

The actual N64 cross-build runs in GitHub Actions unless the libdragon N64 toolchain is installed locally.

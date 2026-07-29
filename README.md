# Full Throttle N64 r2f — libdragon backend bring-up


## r2f change

r2f removes `gui/predictivedialog.o` from this **Full Throttle-only** build. The r2e CI reached `gui/predictivedialog.cpp` and modern GCC rejected its legacy dictionary code. Predictive input is an AGI keyboard feature, while this target enables only SCUMM/SCUMM v7-v8. The upstream ScummVM 1.6.0 source file is not patched; the N64 target simply does not compile unrelated AGI GUI code.

r2f supersedes the legacy `hkz-libn64` experiment from r1.

The target is deliberately narrow:

> Boot and play **Full Throttle** on a Nintendo 64 with an Expansion Pak and
> SummerCart64, with game data and saves on the SummerCart SD card.

This repository does **not** contain the retail game. The CI workflow fetches
ScummVM's publicly distributed DOS Full Throttle demo as the reproducible test
payload and stages it as an SD-card artifact.


## r2f compiler correction

r2f preserves the r2d backend and fixes the next compiler-proven issue: SCUMM
engine sources include headers through the `engines/` include root (for example
`scumm/scumm.h`). The libdragon Makefile now restores the exact include-root
shape used by ScummVM 1.6.0's historical N64 Makefile. No engine source is
patched for this fix.

## What r2f changes

This revision incorporates the first complete two-path CI report:

* fixes libdragon ROM-header metadata (`joypad` -> `n64`) after the standalone probe successfully compiled and linked;
* fixes the ScummVM 1.6.0 graphics API mismatch (`Surface::getPixels()` -> `Surface::pixels`);
* keeps the native libdragon filesystem and staged SD save directory from the previous revision.


* Keeps **ScummVM 1.6.0** as the initial engine baseline because it already has
  Full Throttle / SCUMM v7 support.
* Replaces the old N64 platform assumptions with a new **libdragon** backend, pinned to commit `35f85a0797324a5ed0c723203e33ab3c1da94fdd` (2026-07-15).
* Enables only `SCUMM` + `SCUMM_7_8`.
* Uses libdragon/Newlib file I/O for `sd:/`.
* Uses SD saves at `sd:/fullthrottle/saves/`.
* Adds a standalone `ft64-sd-probe.z64` so hardware SD/display/controller/audio
  can be proven independently of ScummVM.
* CI downloads and stages the official Full Throttle DOS demo.

## Build outputs

The GitHub Action uploads one `full-throttle-n64-r2f-build-report` artifact
containing:

* `ft64-sd-probe.z64` — libdragon/SummerCart hardware probe.
* `full-throttle-n64-r2f.z64` — ScummVM/SCUMM v7 integration ROM if the backend
  compiles and links.
* `sdcard/fullthrottle/` — extracted official demo payload to copy to SD.
* source/patch/build logs and version pins.

The workflow uploads diagnostics even if the ScummVM integration fails. That is
intentional: the first compiler/linker failure is evidence for the next backend
fix, while the independent probe can still be tested on hardware.

## SD layout

Copy the staged `sdcard/fullthrottle/` directory to the SummerCart SD card so
the console sees:

```text
sd:/fullthrottle/
    <Full Throttle demo data>
    saves/
```

The ScummVM executable is launched with:

```text
-p sd:/fullthrottle ft
```

## Controller mapping for r2f

* Analog stick — mouse pointer
* Z — left mouse button
* B — right mouse button
* Start — ScummVM menu (F5)
* L — Escape
* A — period key (kept from the historical N64 mapping for now)

Input can be refined after the game reaches hardware.

## Safety

r2f does **not** use the historical N64 Controller Pak / FlashRAM save managers.
Save files are routed to the SD card.

## Local preflight

```bash
bash ./scripts/preflight.sh
```

The actual N64 cross-build is expected to run in GitHub Actions unless you
already have the current libdragon toolchain installed. The source ZIP does not
duplicate the ~99 MB demo archive; CI fetches the official archive, verifies it,
and packages the extracted demo under the build artifact's `sdcard/fullthrottle/` directory.

## r2f: native libdragon filesystem

r2f is based on the first real CI compiler failure from r2a. The pinned libdragon
Newlib intentionally does not support POSIX `<dirent.h>`. r2f therefore removes
ScummVM's POSIX filesystem shim entirely and supplies a native filesystem adapter
using libdragon `dir_t`, `dir_findfirst()` and `dir_findnext()`. File streams still
use normal `fopen()` through ScummVM's `StdioStream` after `sd:/` is mounted.

The pinned libdragon FAT adapter does not expose a `mkdir` callback, so the build
artifact stages `sd:/fullthrottle/saves/.keep`; runtime code no longer tries to
create directories. Both the standalone probe and ScummVM integration build are
allowed to run in CI even if one fails, so one run captures both compiler logs.

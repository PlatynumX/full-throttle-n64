# Full Throttle N64 r2 — libdragon backend bring-up

r2 supersedes the legacy `hkz-libn64` experiment from r1.

The target is deliberately narrow:

> Boot and play **Full Throttle** on a Nintendo 64 with an Expansion Pak and
> SummerCart64, with game data and saves on the SummerCart SD card.

This repository does **not** contain the retail game. The CI workflow fetches
ScummVM's publicly distributed DOS Full Throttle demo as the reproducible test
payload and stages it as an SD-card artifact.

## What r2 changes

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

The GitHub Action uploads one `full-throttle-n64-r2-build-report` artifact
containing:

* `ft64-sd-probe.z64` — libdragon/SummerCart hardware probe.
* `full-throttle-n64-r2.z64` — ScummVM/SCUMM v7 integration ROM if the backend
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

## Controller mapping for r2

* Analog stick — mouse pointer
* Z — left mouse button
* B — right mouse button
* Start — ScummVM menu (F5)
* L — Escape
* A — period key (kept from the historical N64 mapping for now)

Input can be refined after the game reaches hardware.

## Safety

r2 does **not** use the historical N64 Controller Pak / FlashRAM save managers.
Save files are routed to the SD card.

## Local preflight

```bash
./scripts/preflight.sh
```

The actual N64 cross-build is expected to run in GitHub Actions unless you
already have the current libdragon toolchain installed. The source ZIP does not
duplicate the ~99 MB demo archive; CI fetches the official archive, verifies it,
and packages the extracted demo under the build artifact's `sdcard/fullthrottle/` directory.

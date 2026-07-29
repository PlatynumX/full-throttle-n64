# Evidence / design notes

<<<<<<< HEAD
This file records why r2b is structured this way.
=======
This file records why r2c is structured this way.
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)

## ScummVM baseline

ScummVM 1.6.0's SCUMM module has a separate `ENABLE_SCUMM_7_8` build gate.
That gate selects the v7/v8 pieces used by Full Throttle, including SMUSH,
INSANE, and iMUSE Digital.

The historical N64 Makefile is not a normal configure build and is tied to
`hkz-libn64`, its old MIPS toolchain path, ROMFS, PakFS and FRAMFS.

<<<<<<< HEAD
r2b therefore does not mutate that backend in place. It adds a separate
=======
r2c therefore does not mutate that backend in place. It adds a separate
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
`n64libdragon` platform backend and leaves the old backend untouched as
reference material.

## libdragon baseline

<<<<<<< HEAD
r2b targets libdragon stable `trunk` but pins the tested source snapshot to commit `35f85a0797324a5ed0c723203e33ab3c1da94fdd` (2026-07-15).
=======
r2c targets libdragon stable `trunk` but pins the tested source snapshot to commit `35f85a0797324a5ed0c723203e33ab3c1da94fdd` (2026-07-15).
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)

The current libdragon build system:
* targets `mips64-elf` / VR4300 with the o64 ABI;
* supplies the linker script and N64 ROM packaging tools;
* has current display, audio, joypad, timer and debug APIs;
* exposes SD-backed files through Newlib-style file APIs.

## POSIX filesystem bridge

ScummVM 1.6.0 already has a POSIX filesystem implementation using
`stat`, `opendir`, `readdir` and stdio streams.

<<<<<<< HEAD
libdragon's Newlib integration provides the C/POSIX file layer. r2b therefore
=======
libdragon's Newlib integration provides the C/POSIX file layer. r2c therefore
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
reuses ScummVM's POSIX node implementation with a narrow compile guard
(`N64_LIBDRAGON`) instead of writing another ScummVM filesystem class.

This is the smallest architecture change that lets ScummVM see `sd:/`.


## Upstream references

* ScummVM 1.6.0 N64 Makefile: https://github.com/scummvm/scummvm/blob/v1.6.0/backends/platform/n64/Makefile
* ScummVM 1.6.0 engine gates: https://github.com/scummvm/scummvm/blob/v1.6.0/engines/engines.mk
* libdragon pinned commit: https://github.com/DragonMinded/libdragon/commit/35f85a0797324a5ed0c723203e33ab3c1da94fdd
* libdragon SD/debug API: https://libdragon.dev/ref/debug_8h.html
* official Full Throttle demo listing: https://sourceforge.net/projects/scummvm/files/demos/scumm/

<<<<<<< HEAD
## r2b implementation checks

* The Full Throttle executable calls `assert_memory_expanded()` before creating the ScummVM backend; the standalone probe reports both Expansion Pak state and total RAM without halting.
* ScummVM 1.6.0 uses the N64-specific 555 color masks with R/G/B at bits 11/6/1, which already matches libdragon RGBA5551 color placement. The overlay path therefore preserves the 15 color bits and sets bit 0 opaque instead of shifting the pixel.
* The current libdragon build defaults to C++17; r2b filters that default and builds the 2013 ScummVM code as GNU++11 to reduce avoidable language-version breakage.
=======
## r2c implementation checks

* The Full Throttle executable calls `assert_memory_expanded()` before creating the ScummVM backend; the standalone probe reports both Expansion Pak state and total RAM without halting.
* ScummVM 1.6.0 uses the N64-specific 555 color masks with R/G/B at bits 11/6/1, which already matches libdragon RGBA5551 color placement. The overlay path therefore preserves the 15 color bits and sets bit 0 opaque instead of shifting the pixel.
* The current libdragon build defaults to C++17; r2c filters that default and builds the 2013 ScummVM code as GNU++11 to reduce avoidable language-version breakage.

## CI evidence incorporated in this revision

The previous GitHub build established two concrete compatibility facts:

* The standalone probe compiled and linked to an ELF and reached ROM packaging. `ed64romconfig` then rejected `--controller1 joypad`; its own usage output identifies `n64` as the plain Nintendo 64 controller value. Both ROM makefiles therefore use `N64_ROM_CONTROLLER1=n64`.
* The ScummVM build reached the new backend and failed because ScummVM 1.6.0 `Graphics::Surface` has the public `pixels` member rather than the newer `getPixels()` accessor. The screen-clear path now uses `_game.pixels`.

Both facts are enforced by `scripts/preflight.sh` so neither regression can silently return.
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)

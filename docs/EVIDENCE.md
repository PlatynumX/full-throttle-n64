# Evidence / design notes

This file records why r2f is structured this way.

## ScummVM baseline

ScummVM 1.6.0's SCUMM module has a separate `ENABLE_SCUMM_7_8` build gate.
That gate selects the v7/v8 pieces used by Full Throttle, including SMUSH,
INSANE, and iMUSE Digital.

The historical N64 Makefile is not a normal configure build and is tied to
`hkz-libn64`, its old MIPS toolchain path, ROMFS, PakFS and FRAMFS.

r2f therefore does not mutate that backend in place. It adds a separate
`n64libdragon` platform backend and leaves the old backend untouched as
reference material.

## libdragon baseline

r2f targets libdragon stable `trunk` but pins the tested source snapshot to commit `35f85a0797324a5ed0c723203e33ab3c1da94fdd` (2026-07-15).

The current libdragon build system:
* targets `mips64-elf` / VR4300 with the o64 ABI;
* supplies the linker script and N64 ROM packaging tools;
* has current display, audio, joypad, timer and debug APIs;
* exposes SD-backed files through Newlib-style file APIs.

## POSIX filesystem bridge

ScummVM 1.6.0 already has a POSIX filesystem implementation using
`stat`, `opendir`, `readdir` and stdio streams.

libdragon's Newlib integration provides the C/POSIX file layer. r2f therefore
reuses ScummVM's POSIX node implementation with a narrow compile guard
(`N64_LIBDRAGON`) instead of writing another ScummVM filesystem class.

This is the smallest architecture change that lets ScummVM see `sd:/`.


## Upstream references

* ScummVM 1.6.0 N64 Makefile: https://github.com/scummvm/scummvm/blob/v1.6.0/backends/platform/n64/Makefile
* ScummVM 1.6.0 engine gates: https://github.com/scummvm/scummvm/blob/v1.6.0/engines/engines.mk
* libdragon pinned commit: https://github.com/DragonMinded/libdragon/commit/35f85a0797324a5ed0c723203e33ab3c1da94fdd
* libdragon SD/debug API: https://libdragon.dev/ref/debug_8h.html
* official Full Throttle demo listing: https://sourceforge.net/projects/scummvm/files/demos/scumm/

## r2f implementation checks

* The Full Throttle executable calls `assert_memory_expanded()` before creating the ScummVM backend; the standalone probe reports both Expansion Pak state and total RAM without halting.
* ScummVM 1.6.0 uses the N64-specific 555 color masks with R/G/B at bits 11/6/1, which already matches libdragon RGBA5551 color placement. The overlay path therefore preserves the 15 color bits and sets bit 0 opaque instead of shifting the pixel.
* The current libdragon build defaults to C++17; r2f filters that default and builds the 2013 ScummVM code as GNU++11 to reduce avoidable language-version breakage.

## CI evidence incorporated in this revision

The previous GitHub build established two concrete compatibility facts:

* The standalone probe compiled and linked to an ELF and reached ROM packaging. `ed64romconfig` then rejected `--controller1 joypad`; its own usage output identifies `n64` as the plain Nintendo 64 controller value. Both ROM makefiles therefore use `N64_ROM_CONTROLLER1=n64`.
* The ScummVM build reached the new backend and failed because ScummVM 1.6.0 `Graphics::Surface` has the public `pixels` member rather than the newer `getPixels()` accessor. The screen-clear path now uses `_game.pixels`.

Both facts are enforced by `scripts/preflight.sh` so neither regression can silently return.

## r2f: SCUMM engine include-root correction

The r2d CI build reached the SCUMM engine and failed at `engines/scumm/actor.cpp`
with `fatal error: scumm/scumm.h: No such file or directory`. This is a build-root
issue, not a missing source file. ScummVM 1.6.0's historical N64 Makefile used
`-I./ -I$(srcdir) -I$(srcdir)/engines`; r2f restores that source-layout contract
through `INCLUDES`, which `Makefile.common` folds into `CPPFLAGS`. r2f also stops
manually injecting `$(DEFINES)` into CFLAGS/CXXFLAGS because `Makefile.common`
already does that.

## r2f: predictive dialog compile failure

The r2e CI reached the ScummVM GUI and failed in `gui/predictivedialog.cpp` at the legacy predictive dictionary code (`invalid conversion from 'char' to 'char *'`). This dialog is for AGI predictive keyboard input and is unrelated to Full Throttle. The r2f target therefore filters `gui/predictivedialog.o` from `OBJS` after `Makefile.common` assembles the module list. No upstream ScummVM source file is edited. The target continues to enable only SCUMM and SCUMM v7/v8.

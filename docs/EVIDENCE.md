# Evidence / design notes

This file records why r2a is structured this way.

## ScummVM baseline

ScummVM 1.6.0's SCUMM module has a separate `ENABLE_SCUMM_7_8` build gate.
That gate selects the v7/v8 pieces used by Full Throttle, including SMUSH,
INSANE, and iMUSE Digital.

The historical N64 Makefile is not a normal configure build and is tied to
`hkz-libn64`, its old MIPS toolchain path, ROMFS, PakFS and FRAMFS.

r2a therefore does not mutate that backend in place. It adds a separate
`n64libdragon` platform backend and leaves the old backend untouched as
reference material.

## libdragon baseline

r2a targets libdragon stable `trunk` but pins the tested source snapshot to commit `35f85a0797324a5ed0c723203e33ab3c1da94fdd` (2026-07-15).

The current libdragon build system:
* targets `mips64-elf` / VR4300 with the o64 ABI;
* supplies the linker script and N64 ROM packaging tools;
* has current display, audio, joypad, timer and debug APIs;
* exposes SD-backed files through Newlib-style file APIs.

## POSIX filesystem bridge

ScummVM 1.6.0 already has a POSIX filesystem implementation using
`stat`, `opendir`, `readdir` and stdio streams.

libdragon's Newlib integration provides the C/POSIX file layer. r2a therefore
reuses ScummVM's POSIX node implementation with a narrow compile guard
(`N64_LIBDRAGON`) instead of writing another ScummVM filesystem class.

This is the smallest architecture change that lets ScummVM see `sd:/`.


## Upstream references

* ScummVM 1.6.0 N64 Makefile: https://github.com/scummvm/scummvm/blob/v1.6.0/backends/platform/n64/Makefile
* ScummVM 1.6.0 engine gates: https://github.com/scummvm/scummvm/blob/v1.6.0/engines/engines.mk
* libdragon pinned commit: https://github.com/DragonMinded/libdragon/commit/35f85a0797324a5ed0c723203e33ab3c1da94fdd
* libdragon SD/debug API: https://libdragon.dev/ref/debug_8h.html
* official Full Throttle demo listing: https://sourceforge.net/projects/scummvm/files/demos/scumm/

## r2a implementation checks

* The Full Throttle executable calls `assert_memory_expanded()` before creating the ScummVM backend; the standalone probe reports both Expansion Pak state and total RAM without halting.
* ScummVM 1.6.0 uses the N64-specific 555 color masks with R/G/B at bits 11/6/1, which already matches libdragon RGBA5551 color placement. The overlay path therefore preserves the 15 color bits and sets bit 0 opaque instead of shifting the pixel.
* The current libdragon build defaults to C++17; r2a filters that default and builds the 2013 ScummVM code as GNU++11 to reduce avoidable language-version breakage.

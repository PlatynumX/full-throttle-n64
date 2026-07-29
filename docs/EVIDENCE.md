# Evidence / design notes — r2k

## Pinned sources

ScummVM is pinned to tag `v1.6.0`, resolved and checked against commit:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

libdragon is pinned to:

```text
35f85a0797324a5ed0c723203e33ab3c1da94fdd
```

The build refuses to continue if the fetched ScummVM tag resolves to any other commit.

## Full Throttle engine scope

ScummVM 1.6.0's SCUMM module has a separate `ENABLE_SCUMM_7_8` gate. That gate adds the v7/v8 objects used by Full Throttle, including iMUSE Digital, INSANE and SMUSH.

The N64 target enables only:

```makefile
ENABLE_SCUMM := STATIC_PLUGIN
ENABLE_SCUMM_7_8 := STATIC_PLUGIN
```

AGI is not enabled.

## Why r2f repeated the predictive-dialog error

The r2e/r2f compiler reached `gui/predictivedialog.cpp` and modern GCC rejected a legacy conversion in that source.

r2f attempted to remove `gui/predictivedialog.o` from top-level `OBJS` after including `Makefile.common`. That could not work.

ScummVM 1.6.0 `Makefile.common` first includes every module's `module.mk`. `rules.mk` then transforms each static module's object list into a module archive and appends the archive to top-level `OBJS`:

```text
gui/*.o -> gui/libgui.a -> top-level OBJS
```

By the time the r2f filter ran, `gui/predictivedialog.o` had already become a prerequisite of `gui/libgui.a`. The r2f filter is removed entirely in r2i.

## r2i source change

r2i always starts with the pristine pinned ScummVM tree and applies exactly one normal Git patch:

```text
upstream/scummvm-1.6.0-ft64.patch
```

That patch removes `predictivedialog.o` from `gui/module.mk` before `Makefile.common` constructs the GUI archive rule. It does not edit `predictivedialog.cpp` and does not use `sed`, regex replacement, or a chain of generated patchers.

`git apply --check` must pass before the source is changed.

## Dependency-graph proof

After integration and before compilation, r2i runs `make -pn` against the actual pinned ScummVM + libdragon Makefile and records the generated make database.

The build is stopped unless:

* `gui/libgui.a` exists in that database and has no `gui/predictivedialog.o` prerequisite;
* `engines/scumm/libscumm.a` contains `engines/scumm/insane/insane.o`;
* it contains `engines/scumm/smush/smush_player.o`;
* it contains `engines/scumm/imuse_digi/dimuse.o`.

This is the guard that r2f was missing.


## r2g final-link failure and r2i correction

r2g reached the final ELF link, proving the Full Throttle-only ScummVM source set compiled. The linker failed with `linker script file 'n64.ld' appears multiple times`.

Pinned libdragon `n64.mk` defines `N64_LDFLAGS` with `-Tn64.ld` and appends `N64_LDFLAGS` as a target-specific `LDFLAGS` value on `%.z64`. That target-specific value is inherited by the ELF prerequisite. r2g also initialized global `LDFLAGS` from `N64_LDFLAGS`, producing two copies. The same duplication affected C/C++/assembler platform flags.

r2i therefore does not copy any `N64_*FLAGS` variable into generic flags. It normalizes libdragon's `N64_CFLAGS`/`N64_CXXFLAGS` once (removing `-Werror` and selecting C++11), then lets libdragon propagate them. The generic `CXXFLAGS` contains only the ScummVM-specific `-fno-rtti -fno-exceptions` delta.

Before compilation, integration now performs a GNU make dry run of `full-throttle-n64-r2i.z64`, captures the exact final G++ link command, and requires exactly one `-Tn64.ld`.

## Prior compiler-proven corrections retained

Earlier CI runs established:

* libdragon ROM metadata uses `N64_ROM_CONTROLLER1=n64`, not `joypad`;
* ScummVM 1.6.0 `Graphics::Surface` uses the public `pixels` member rather than `getPixels()`;
* SCUMM sources expect the `engines/` include root so `scumm/scumm.h` resolves;
* the pinned libdragon toolchain does not provide POSIX `<dirent.h>`, so the backend uses libdragon's native directory API;
* the mounted FAT adapter does not provide runtime directory creation, so `saves/` is staged in the SD payload.

Each retained correction has a preflight regression guard.

## Filesystem architecture

The backend supplies `N64LibdragonFilesystemNode` rather than ScummVM's POSIX filesystem implementation. Directory enumeration uses:

```text
dir_t
dir_findfirst()
dir_findnext()
```

File streams use ScummVM `StdioStream` over libdragon/Newlib after `sd:/` is mounted.

## Historical N64 backend

The old ScummVM N64 backend remains useful reference material but is not linked into this target. r2i does not use hkz-libn64, ROMFS, PakFS or FRAMFS.

## r2i: linker-audit false negative

The r2h CI integration step failed before compilation because its audit captured only
the first physical line of libdragon's final g++ recipe. In pinned libdragon n64.mk,
the g++ invocation is continued onto the following line, where `$(LDFLAGS)` expands;
therefore `-Tn64.ld` was not present in the single captured line even though it is
present in the actual executable link branch. r2i audits the complete first g++
branch through its `-Wl,-Map=...;` terminator. The backend flag-ownership change from
r2h is unchanged.


## r2k: final ROM packaging title

The r2i ScummVM build compiled and linked through `full-throttle-n64-r2i.elf`, then failed when libdragon invoked `n64tool`. The generated command expanded the backend title as separate shell words before `--output`, causing `n64tool` to treat those words as input files and report `Need output flag before first file`.

Pinned libdragon defines `N64_TOOLFLAGS = --title $(N64_ROM_TITLE)` and its own default `N64_ROM_TITLE` includes quotes. r2k follows that contract directly:

```makefile
N64_ROM_TITLE := "Full Throttle N64"
```

The title is 17 characters, within `n64tool`'s 20-character title limit. Integration dry-runs the actual final `.z64` target and refuses to compile unless the emitted `n64tool` command contains the quoted title immediately before `--toc --output full-throttle-n64-r2k.z64`.

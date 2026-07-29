# Full Throttle N64 r2k

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

## Why r2k exists

r2j did not reach either N64 build. Its integration audit stopped first. The screenshot showed `grep: write error: Broken pipe`, and the exact r2j script contained multiple `grep | head -1` and `printf | grep -q` inspection pipelines while running with `set -euo pipefail`. Those short-circuiting consumers are inappropriate for validation under pipefail.

r2k does not change the ScummVM backend, Full Throttle engine selection, linker ownership, or quoted ROM title. It replaces those audit pipelines with single-process `awk` first-match extraction and Bash string comparisons, and it prints the exact generated `n64tool` command it validated. The workflow's toolchain-version capture was also changed to avoid `head` in a pipeline.

r2g compiled the complete ScummVM/SCUMM target and reached the final libdragon link. The linker then rejected the command because `n64.ld` appeared twice.

The cause is in the backend Makefile's flag ownership, not in ScummVM: the backend copied `N64_CFLAGS`, `N64_CXXFLAGS`, `N64_ASFLAGS`, and `N64_LDFLAGS` into the generic flags, while pinned libdragon `n64.mk` also appends those same `N64_*` variables from its `%.z64` target to the complete prerequisite chain. GNU make target-specific variables are inherited by prerequisites, so the ELF link received two copies of `N64_LDFLAGS`, including two `-Tn64.ld` flags. The earlier compile logs also showed duplicated compile flags for the same reason.

r2i fixed the ownership model: libdragon alone supplies platform flags; the backend generic flags contain only ScummVM-specific deltas such as `-fno-rtti -fno-exceptions`. That build then compiled and linked the complete target, proving the duplicate-linker-script issue was gone.

r2k addresses the next observed failure only: libdragon ROM packaging. The r2i `N64_ROM_TITLE` was a bare multi-word value, so `n64tool` received title words as separate arguments before `--output`. r2k uses a quoted 17-character title and verifies the generated packaging command before compilation.

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

The GitHub Action uploads `full-throttle-n64-r2k-build-report` containing diagnostics plus, when successful:

```text
ft64-sd-probe.z64
full-throttle-n64-r2k.z64
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

### r2i audit correction
r2i keeps the r2h libdragon flag-ownership model unchanged. It corrects the CI dry-run
audit to inspect the complete multi-line g++ link branch emitted by pinned libdragon,
so `-Tn64.ld` is counted where it is actually expanded rather than only on the first
physical recipe line.

### r2k ROM-packaging correction

r2i completed the final ELF link and reached libdragon's `n64tool` ROM packaging step. Packaging failed with `Need output flag before first file` because the backend set an unquoted multi-word `N64_ROM_TITLE`. Pinned libdragon expands `N64_TOOLFLAGS` as `--title $(N64_ROM_TITLE)` and therefore requires a multi-word title to carry its own shell quotes. r2k uses the stable 17-character title `"Full Throttle N64"` and audits the actual `make -n` `n64tool` command before compilation.

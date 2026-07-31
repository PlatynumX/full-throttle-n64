# Full Throttle N64 r2v — Full Throttle-only static pruning

r2v keeps the proven r2u memory diagnostics while removing compile-time roots for game engines and support systems that Full Throttle cannot use.

## Source specialization

`N64_FT_ONLY` makes the pinned ScummVM build instantiate only SCUMM v7 Full Throttle, the standard GDI, standard Sound manager, classic charset renderer, AKOS costumes, normal actors, and iMUSE Digital. It compiles out the old MIDI/player selection tree, Scumm debugger instance, launcher, event recorder, generic music-plugin manager, and YUV manager roots.

`DISABLE_HELP` and `DISABLE_TOWNS_DUAL_LAYER_MODE` remove two more irrelevant paths. The library object lists remain intact for compile safety; `--gc-sections` removes archive members once these runtime roots are gone.

## Backend memory

The libdragon display queue changes from three 320x240x16 buffers to two, recovering about 150 KiB of heap. The converted game surface and overlay remain unchanged to avoid regressing the established transition path.

## Evidence

The build artifact preserves the ELF, link map, address/size symbol tables, a static-size comparison against r2u (3,836,317 bytes), and a pruned-symbol audit. Runtime USB diagnostics remain enabled so the music allocation can be retested directly.

Outputs: `ft64-sd-probe-r2v.z64`, `full-throttle-n64-r2v.z64`.


## Reproducible source application

The three large pinned source files are not carried as context-sensitive diffs.
`scripts/specialize_ft_only.py` performs exact literal one-match edits and fails
if the pinned source differs in any targeted block. The smaller established
INSANE/SMUSH/GUI changes remain an ordinary exact four-file patch. The updater
and CI both run the same two-stage source application and `git diff --check`.


## Structural Full Throttle specialization

`scripts/specialize_ft_only.py` uses unique normalized line anchors, balanced
brace scanning, and preprocessor nesting rather than multiline source-string
replacement. The updater and CI run separate check, apply, and verify phases.
No source file is written until all three in-memory transformations validate.

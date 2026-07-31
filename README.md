# Full Throttle N64 r2u — memory map diagnostics

r2u measures where the Expansion Pak memory is going before changing runtime
behavior.

## Runtime evidence

SummerCart USB logs now include:

```text
[FT64DIAG r2u] MEM tag=... physical=... outside=... heap=used/total free=...
[FT64DIAG r2u] NEW seq=... size=... caller=... heap=used/total free=...
```

Heap checkpoints cover display initialization, input/timer, audio, the CLUT8
game surface, the converted 16-bit game surface, overlay allocation, filesystem
factory, save manager, timer manager, mixer, event backend, game-surface resize,
first update, first input poll, and SMUSH begin/end/release.

The allocator threshold is 16 KiB. Each logged allocation includes the return
address of the code that requested it. Failed allocations are always logged.

## Build-time evidence

The build report preserves the exact ELF plus:

```text
r2u-elf-size.txt
r2u-elf-sections.txt
r2u-elf-readelf-sections.txt
r2u-elf-readelf-segments.txt
r2u-elf-objdump-sections.txt
r2u-elf-symbols-by-address.txt
r2u-elf-symbols-by-size.txt
r2u-largest-400-symbols.txt
r2u-static-memory-summary.txt
```

The address-ordered symbol file lets the runtime `caller=` addresses be mapped
back to exact functions.

## Scope

This is diagnostic only. It keeps the r2t renderer, audio, input, SD/save,
SMUSH timing, overlay transition, and allocation-failure behavior unchanged.

The main ROM still expects an Expansion Pak and game data at:

```text
sd:/fullthrottle/
```

Outputs:

```text
ft64-sd-probe-r2u.z64
full-throttle-n64-r2u.z64
```

Artifact: `full-throttle-n64-r2u-build-report`.

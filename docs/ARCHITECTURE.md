# r2g architecture

## Engine

```text
ScummVM 1.6.0 @ f75a652bb7c956f145abe881c87b5dbf5c9ec24b
    |
    +-- SCUMM
         +-- SCUMM v7/v8
              +-- SMUSH
              +-- INSANE
              +-- iMUSE Digital
```

The build is intentionally Full Throttle-only. It is not an attempt to restore every ScummVM engine on N64.

## Platform

```text
OSystem_N64Libdragon
    |
    +-- video: 320x240 libdragon display, 16-bit output
    +-- audio: libdragon audio buffers
    +-- input: libdragon joypad
    +-- timer: libdragon tick source, ScummVM timer manager pumped outside IRQ context
    +-- files: native N64LibdragonFilesystemNode + libdragon dir API
    +-- streams: stdio over mounted sd:/
    +-- saves: sd:/fullthrottle/saves/
    +-- debug: libdragon USB/emulator logging
```

## Source integration

Every build fetches a pristine pinned ScummVM tree. Complete platform source files are copied from `backend/` into a new `backends/platform/n64libdragon/` directory.

One upstream patch removes the AGI-only predictive-input object from `gui/module.mk` before module archive rules are created. The generated make database is audited before compilation.

## Standalone probe

`ft64-sd-probe.z64` proves the hardware/platform layer independently. It initializes video, controller and audio, mounts `sd:/`, enumerates `sd:/fullthrottle/`, and performs a file write/read test in the existing directory.

This lets us distinguish a SummerCart/libdragon failure from a ScummVM engine/backend failure.

## First runtime risks after a successful link

Once the demo boots, the next unknowns become measured runtime behavior rather than build speculation: SMUSH decoding throughput, iMUSE Digital mixing load, INSANE sequences, memory pressure, SD streaming behavior and save/load behavior.

# r2d architecture

## Engine side

Pinned initial baseline:

* ScummVM 1.6.0
* SCUMM engine enabled
* SCUMM v7/v8 subengine enabled

That subengine brings the Full Throttle-required SCUMM v7 code paths, including
the SMUSH/INSANE/iMUSE Digital objects selected by ScummVM's own build rules.

## Platform side

Historical N64 dependencies are not used:

```text
hkz-libn64              REMOVED
romfs game payload      REMOVED
pakfs save manager      REMOVED
framfs save manager     REMOVED
```

New platform path:

```text
ScummVM 1.6.0
   |
   +-- SCUMM v7 / Full Throttle
   |
   +-- OSystem_N64Libdragon
         |
         +-- display: libdragon 320x240 / RGBA5551
         +-- audio:   libdragon AI buffers
         +-- input:   libdragon joypad
         +-- timer:   libdragon COP0 timer
         +-- files:   ScummVM POSIX filesystem node over Newlib
         +-- saves:   DefaultSaveFileManager("sd:/fullthrottle/saves")
         +-- logs:    libdragon emulator/USB debug
```

## Why a standalone probe exists

A backend migration has two independent unknowns:

1. Can current libdragon on the user's SummerCart mount and use the SD card the
   way we expect?
2. Can a 2013 ScummVM tree be made to compile/link cleanly against a current
   GCC/Newlib/libdragon platform?

`ft64-sd-probe.z64` answers #1 without depending on #2.

The probe:
* initializes 320x240 video;
* initializes a controller;
* mounts `sd:/`;
* reads `sd:/fullthrottle/`;
* creates/writes/reads `sd:/fullthrottle/ft64-r2d-probe.txt`;
* initializes the audio subsystem;
* reports status on screen and through debug output.

## First performance risks after boot

The backend itself is not expected to be the hard part. Full Throttle's SCUMM
v7 workload includes SMUSH video, INSANE bike sequences and iMUSE Digital
audio. Once the demo boots, those become measurement targets rather than
speculation.

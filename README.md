# Full Throttle N64 r2r — retail transition diagnostics

r2r is a deliberately sparse diagnostic build based on the verified r2q
ScummVM timing backport. Its immediate target is the retail-CD behavior observed
on hardware: the opening SMUSH movie completes and the display then goes black.

No renderer optimization is being attempted in this revision. The point is to
separate four cases with SummerCart USB evidence:

1. SMUSH never exits cleanly.
2. SMUSH exits but the SCUMM event/main loop stops advancing.
3. The loop advances but no new screen presentation occurs.
4. A retail resource/path lookup fails around the transition.

## Runtime markers

The libdragon backend already sends debug output to USB and emulator logs.
r2r adds a low-volume `[FT64DIAG r2r]` stream:

- boot/backend initialization;
- video `initSize`;
- one heartbeat per second from rendering or `pollEvent`, including cumulative
  update, poll, present, copy, full-frame, and palette counters;
- overlay show/hide/clear transitions;
- the first 96 missing paths under `sd:/fullthrottle/`;
- the first 192 Full Throttle filesystem open/write operations;
- SMUSH begin, EOF, loop exit, and post-release markers.

The filesystem counters are capped and SMUSH logging is transition-only so USB
traffic does not become a frame-by-frame performance perturbation.

## Full retail data

The executable remains data-agnostic between demo and retail and launches:

```text
-p sd:/fullthrottle ft
```

No copyrighted Full Throttle data is downloaded, embedded, or packaged.

## Pinned source

ScummVM:
`f75a652bb7c956f145abe881c87b5dbf5c9ec24b`

libdragon:
`35f85a0797324a5ed0c723203e33ab3c1da94fdd`

The one ScummVM patch still touches only:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

Its SHA-256 is:

```text
01b2dda2caf28995090bf68158a7f0371ac6bebfb7e6a3991d08669bccec298d
```

The update bundle validates that patch against the exact pristine pinned files
saved by the r2o CI artifact before it is allowed to touch GitHub.

## Build output

```text
ft64-sd-probe-r2r.z64
full-throttle-n64-r2r.z64
```

Artifact:

```text
full-throttle-n64-r2r-build-report
```

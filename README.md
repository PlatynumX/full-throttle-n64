# Full Throttle N64 r2t — allocator diagnostics

This is the corrected r2t diagnostic build for the retail Full Throttle
allocation crash.

## What r2s proved

The r2s CI run stopped before compilation because its `resource.cpp` diagnostic
hunk did not apply to the real pinned ScummVM source. That patch is discarded.

## r2t design

The one ScummVM patch is back to the four exact files already validated by the
r2q/r2r integration work:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

`resource.cpp` is untouched.

Heap telemetry is instead placed at the N64 backend's global `operator new` and
`operator new[]` boundary—the allocation path reached by the crash trace.

Large allocations and every failed allocation report:

```text
[FT64DIAG r2t] NEW phase=request kind=array size=...
[FT64DIAG r2t] NEW phase=allocated kind=array size=...
[FT64DIAG r2t] NEW phase=failed kind=array size=...
```

Each line includes requested bytes and libdragon heap used, total, and free
bytes. Logging is enabled only after USB debug initialization and guarded
against recursive diagnostic allocation.

The backend is compiled with `-fno-exceptions`, so allocation failure is logged
and then stopped with `abort()` rather than using a C++ throw.

Existing r2r/r2s filesystem, SMUSH lifecycle, screen heartbeat, overlay,
controller, SD, and save diagnostics remain.

No game data is included or fetched. Runtime data remains at:

```text
sd:/fullthrottle/
```

Outputs:

```text
ft64-sd-probe-r2t.z64
full-throttle-n64-r2t.z64
```

Artifact: `full-throttle-n64-r2t-build-report`.

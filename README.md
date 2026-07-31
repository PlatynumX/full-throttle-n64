# Full Throttle N64 r2s — heap diagnostics

Full Throttle-only ScummVM 1.6.0 port for Nintendo 64/libdragon.

## Why r2s exists

The r2r SummerCart trace reached retail Full Throttle gameplay content and then
terminated in `operator new` while `ResourceManager::createResource()` was
loading an iMUSE sound resource. The file-open diagnostics showed no missing CD
files around that crash.

r2s keeps all r2r SMUSH, filesystem, renderer, input, SD/save, and transition
diagnostics and adds allocation telemetry at the exact resource allocator.

## Runtime output

Each heartbeat now includes libdragon heap usage and free bytes. Sound-resource
and >=64 KiB resource allocations emit four snapshots:

```text
[FT64DIAG r2s] RES phase=request ...
[FT64DIAG r2s] RES phase=after-nuke ...
[FT64DIAG r2s] RES phase=after-expire ...
[FT64DIAG r2s] RES phase=allocated ...
```

Each line includes resource type/id, requested bytes, ScummVM resource-cache
bytes, minimum/maximum cache thresholds, and real libdragon heap used/total/free.
If `after-expire` is the final line before `operator new`, its numbers distinguish
insufficient free memory from likely heap fragmentation.

No retail/demo data is included or fetched. Game data remains on
`sd:/fullthrottle/`.

Build outputs:

```text
ft64-sd-probe-r2s.z64
full-throttle-n64-r2s.z64
```

Artifact: `full-throttle-n64-r2s-build-report`.

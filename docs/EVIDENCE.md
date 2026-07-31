# Evidence — r2s heap diagnostics

## Observed r2r failure

The hardware trace ended in this call chain:

```text
operator new
ResourceManager::createResource
ScummEngine::readSoundResource
ImuseDigiSndMgr::openSound
IMuseDigital::startMusic
IMuseDigital::playFtMusic
```

The crash occurred after successful opens of the retail Full Throttle data and
video files. r2s therefore diagnoses allocation pressure before changing cache,
music, or renderer behavior.

## Pinned contracts

ScummVM: `f75a652bb7c956f145abe881c87b5dbf5c9ec24b`

libdragon: `35f85a0797324a5ed0c723203e33ab3c1da94fdd`

The pinned libdragon header exposes `heap_stats_t { total, used }` and
`sys_get_heap_stats(heap_stats_t *)`. r2s calls that exact API.

## Consolidated source patch

SHA-256:

```text
9a90e18017552355e2e75eb0a5615f469273892d316a4e84a51d1157dcfbc041
```

It touches exactly:

```text
engines/scumm/insane/insane.cpp
engines/scumm/resource.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

The resource instrumentation does not alter allocation size, cache expiry, or
exception behavior. It snapshots before/after the existing nuke/expiry path and
after successful allocation.

## Backend delta

SHA-256:

```text
6db298a043414edef8d1b630ce338ebf15758a0ee7a270c3feca5c6ac492ebd1
```

The delta is generated from the exact reconstructed r2r backend that produced
the uploaded hardware logs. It relabels markers to r2s, adds the resource-heap
bridge, and appends heap stats to the one-second heartbeat.

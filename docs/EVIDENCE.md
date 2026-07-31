# Evidence / design notes — r2u

## Exact r2t baseline

The updater requires these exact live backend files before it changes anything:

```text
backend/osys_n64_libdragon.cpp
9a9bd01d9ad65f7251ac6f449407791b0650e5a3025af174efc29f0da878e323

backend/n64libdragon-fs.cpp
4db29d02596a5efa7be4c1c941a16a0121abd1d7129dee8cd254fb37752572b1
```

The exact r2t ScummVM patch SHA-256 is:

```text
e1af9d2c0a4f8e6a0c745817ba931e214e53e5ebd7091118a831838c70fd35bf
```

## r2u patches

The backend memory-map patch SHA-256 is:

```text
3672c1e3a305ba86c83cbf0980efad26ac6077be04df78362f53e9fed215c997
```

The consolidated pristine-source-to-r2u ScummVM patch SHA-256 is:

```text
4d4735eae951e7c1668825f8a7a073b82b2483f004c26b1c9fc722f60a66f194
```

The ScummVM patch still touches exactly:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

`resource.cpp` remains untouched.

## Memory accounting

`MEM` checkpoints report physical RAM, the fixed malloc-heap capacity, heap
used/free, and bytes outside the malloc heap. Deltas between adjacent tags
isolate libdragon display/audio reservations and backend surface allocations.

`NEW` entries report allocations of 16 KiB or larger, allocation sequence,
object/array form, request/result, requesting return address, and heap state.
The build report includes the exact ELF and address-sorted symbols needed to
resolve those caller addresses.

No optimization is mixed into this revision. No fuzzy patching, `--3way`,
source regex mutation, or fallback patch is used.

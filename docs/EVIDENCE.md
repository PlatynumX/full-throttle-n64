# Evidence / design notes — r2r

## Observed hardware symptom

Using retail Full Throttle CD data from `sd:/fullthrottle/`, an earlier ROM
plays the opening SMUSH movie but goes black immediately when the movie ends.
The r2q ROM had not yet been established as the tested runtime at the time this
diagnostic branch was requested.

r2r therefore does not infer that the frame-rate backport caused the black
screen. It instruments the transition instead.

## ScummVM evidence

Pinned ScummVM:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

The r2r ScummVM patch was generated from the exact pristine files preserved in
the uploaded r2o build report. It retains the r2q timing backport and adds only
four sparse SMUSH warning markers:

```text
SMUSH begin
SMUSH eof
SMUSH loop-exit
SMUSH released
```

Those warnings flow through the existing OSystem log callback into libdragon's
debug output.

Patch SHA-256:

```text
01b2dda2caf28995090bf68158a7f0371ac6bebfb7e6a3991d08669bccec298d
```

The bundle runs exact `git apply --check`, applies the patch once to the saved
fixture, runs `git diff --check`, and asserts all four expected source paths and
diagnostic markers before touching the GitHub repository.

## Backend evidence

The project backend already initializes libdragon USB/emulator logging and its
normal log callback forwards ScummVM messages into that channel. r2r adds:

- a one-second heartbeat reachable from both `updateScreen()` and `pollEvent()`;
- presentation/copy/palette counters;
- overlay transition markers;
- capped Full Throttle filesystem-open and missing-path markers.

The backend project patch SHA-256 is:

```text
b7feea28fde2339370611be934e685b1f997940aa1f4505555f02e76e571d46a
```

Unlike the pinned ScummVM fixture, the update bundle does not carry a second
copy of the project backend as a validation fixture. Instead it fresh-clones the
live project and requires an exact `git apply --check` against that clone before
the backend diagnostics can be applied. A context mismatch aborts the update;
there is no fuzzy or 3-way fallback.

## Noise control

There is no per-frame SMUSH logging. Filesystem misses stop after 96 entries,
filesystem open/write diagnostics stop after 192 operations, and the heartbeat
is limited to about once per second. This keeps the diagnostic build useful
without turning USB logging itself into the primary video workload.

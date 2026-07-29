# Evidence / design notes — r2q

## Exact source evidence

ScummVM is pinned to:

```text
f75a652bb7c956f145abe881c87b5dbf5c9ec24b
```

libdragon is pinned to:

```text
35f85a0797324a5ed0c723203e33ab3c1da94fdd
```

The uploaded r2o CI report preserved the exact pristine ScummVM files touched by
the source patch. They establish the real 1.6.0 layout:

- `SmushPlayer::handleAnimHeader()` starts at line 906;
- `Insane::smush_setupSanWithFlu()` starts at line 1402;
- `Insane::smush_setupSanFromStart()` starts at line 1444;
- `_smush_setupsan2` is the existing SAN-flags field;
- AHDR has a six-byte prefix followed by the 0x300-byte palette.

## r2o failure evidence

The integration log failed at exact `git apply --check` before either N64 build
ran. Replaying the failed r2o patch with `git apply --check --verbose` against
the preserved pristine files shows three context mismatches caused by omitted
blank lines. The first INSANE hunk and constructor hunk relocate successfully,
which also confirms the pinned checkout is the intended source generation.

r2q does not patch the patch or add a fallback. Its one Git patch was generated
directly from those pristine files.

## Upstream timing behavior

Upstream ScummVM commit
`9e7e6a08b276ebe5dfdbc79e9a9fc2edcfd12bf8` implements video-dependent frame
rates for Full Throttle and the DIG demo. r2q carries only the Full Throttle
behavior needed by this build and adapts it to the verified 1.6.0 layout.

The encoded rate is read after the six-byte AHDR prefix and 0x300-byte palette
for header major versions greater than 1. SAN flag bit 3 suppresses the
override. The N64 adaptation reads directly from the existing stream rather than
allocating a complete AHDR copy.

## Patch policy

Exactly one ScummVM patch touches:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

Validated patch SHA-256:

```text
38ddda23037b45da9c7842245c6442eea8096a029b7141382a43d341a366ca54
```

The update bundle proves this patch against the exact CI-preserved source fixture
before publishing. CI independently proves it against a clean pinned checkout
before compiling.

No fuzzy application, `--3way`, regex rewrite, sed source mutation, or secondary
patch is permitted.

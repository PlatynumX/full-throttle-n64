# Evidence / design notes — r2v

Exact r2u baseline backend hashes:

- osys: `dfeb6b23de874d7949b69d600c43ca5cf1122dd0321c31a4e1a51443eb77f1f9`
- filesystem: `e0327d775414d13e88ed0bd4c4dac4edc6d94b60cd67ff7435df2f1a0bffa259`
- ScummVM patch: `4d4735eae951e7c1668825f8a7a073b82b2483f004c26b1c9fc722f60a66f194`

r2v patches:

- backend double-buffer patch: `6d9da236dfd6a7ae4c3a11437d54531c7b48b5a1f4a1e58b9578cc1d541dfdca`
- exact four-file runtime patch: `a7615a68561b8977b982aa3a9bbaa229a6ab2b059f7ea0cc180391af114441cf`
- deterministic FT-only specializer: `6146242613f28c98bfe38de4d812c25bd58957e2a8a0a3befe305e9580048efb`

The ScummVM patch touches exactly `base/main.cpp`, `engines/scumm/detection.cpp`, `engines/scumm/scumm.cpp`, the three already-validated INSANE/SMUSH files, and `gui/module.mk`. `resource.cpp` remains untouched.

The updater downloads the three newly touched pristine files directly from the pinned ScummVM commit and combines them with the four exact packaged fixtures before running `git apply --check`, `git apply`, and `git diff --check`. CI repeats the check against a clean full checkout.

No module object list is manually shortened in r2v. The pruning is source-controlled and relies on the already-active function/data sections plus linker garbage collection.


## Corrected updater v2

The first r2v package stopped during its local validation before cloning or
modifying GitHub. Its first three diffs (`base/main.cpp`,
`engines/scumm/detection.cpp`, and `engines/scumm/scumm.cpp`) were malformed and
did not apply to the exact pinned files.

The corrected seven-file patch was regenerated with full pinned-source context.
The original INSANE/SMUSH/GUI portions are retained. The first three files are
downloaded from the pinned commit and byte-count checked before an exact verbose
`git apply --check`.

The first package also contained a contradictory preflight rule that rejected
`engines/scumm/scumm.cpp`, despite that file being an intentional member of the
seven-file Full Throttle specialization. That rule is removed; the preflight now
requires the `scumm.cpp` diff and rejects only the unnecessary `insane.h` path.

Corrected patch SHA-256:

```text
60fad79a81531d3943ba0aeabe3335ea36f01159734809ada6d567c947be2c3b
```


## Corrected updater v3

The v2 log proved that the first three diffs still did not apply to the real
pinned files. Their prior local validation used incomplete synthetic source
fixtures, so that result was invalid.

v3 removes those three diffs. The runtime patch now touches exactly:

```text
engines/scumm/insane/insane.cpp
engines/scumm/smush/smush_player.cpp
engines/scumm/smush/smush_player.h
gui/module.mk
```

The immutable pinned `base/main.cpp`, `detection.cpp`, and `scumm.cpp` files are
processed by `scripts/specialize_ft_only.py`. Each transformation checks that
its exact old block occurs once before writing. The updater first runs this on
files downloaded directly from pinned commit
`f75a652bb7c956f145abe881c87b5dbf5c9ec24b`; CI repeats it on the clean checkout.

Runtime patch SHA-256: `a7615a68561b8977b982aa3a9bbaa229a6ab2b059f7ea0cc180391af114441cf`

Specializer SHA-256: `6146242613f28c98bfe38de4d812c25bd58957e2a8a0a3befe305e9580048efb`


## Corrected updater v4

The uploaded v3 transcript showed that its exact four-file runtime patch passed,
then the old specializer failed before cloning GitHub:

```text
base/main.cpp: open launcher guard: expected exactly one source match, found 0
```

The v4 specializer no longer performs exact multiline `str.replace` operations.
It locates unique stripped lines, balanced C++ brace regions, and nested
preprocessor regions. It builds and verifies all three outputs in memory before
`--apply` writes any source file.

The updater and CI both execute:

```text
--check
--apply
--verify
git diff --check
```

The v4 specialization additionally guards the Full Throttle-irrelevant CD audio
setup and FM-Towns volume hook.

Runtime patch SHA-256: `a7615a68561b8977b982aa3a9bbaa229a6ab2b059f7ea0cc180391af114441cf`

Structural specializer SHA-256: `3e03af9adedcdd5eb338864f58bb48750044f47d32dbf3c1c888e4b397a90d9c`

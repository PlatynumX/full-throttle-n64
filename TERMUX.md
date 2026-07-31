# Full Throttle N64 r2t — Termux

Use the corrected `full-throttle-n64-r2t-allocator-diagnostics-update-v2.zip`.

The updater first proves the four-file ScummVM patch against the exact pinned
fixture and proves the allocator patch against the exact reconstructed r2s
backend included in the package.

It then fresh-clones GitHub, verifies the live project is still the failed r2s
baseline, applies the backend patch exactly, installs r2t, runs preflight,
checks the exact staged path set, and refuses to push if master moves.

No game/demo data is fetched or packaged.

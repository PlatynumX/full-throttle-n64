# Full Throttle N64 r2q — Termux

The r2q update bundle advances the current failed-r2o repository without a
hard-coded live GitHub commit SHA.

It first validates the corrected patch against the exact pinned ScummVM files
preserved by r2o CI. It then fresh-clones GitHub, proves the live tree is the
known failed-r2o baseline, captures that exact commit, installs r2q, runs
preflight, enforces the exact staged file set, and refuses to push if the remote
moves.

No Full Throttle game/demo data is fetched or packaged.

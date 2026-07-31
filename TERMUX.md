# Full Throttle N64 r2v — Termux

The corrected v4 updater validates the real pinned ScummVM files before cloning
or modifying GitHub. It exact-applies the established INSANE/SMUSH/GUI patch,
runs structural Full Throttle-only check/apply/verify passes on `main.cpp`,
`detection.cpp`, and `scumm.cpp`, validates the combined seven changed paths,
applies the double-buffer backend patch, runs complete preflight, commits, and
pushes only if remote master has not moved.

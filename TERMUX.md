# Full Throttle N64 r2u — Termux

The r2u updater advances the exact r2t diagnostic tree.

It validates both r2u patches against exact fixtures, fresh-clones GitHub,
proves the live tree still has the exact r2t source/backend hashes, applies the
backend patch exactly, installs r2u, runs preflight, checks the exact staged path
set, and refuses to push if master moves.

After the build, keep the GitHub `full-throttle-n64-r2u-build-report` artifact.
It contains the ELF and symbol table needed to resolve runtime allocation
caller addresses.

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LD="$ROOT/work/libdragon"

: "${N64_INST:?N64_INST must point at the libdragon toolchain prefix}"
test -x "$N64_INST/bin/mips64-elf-gcc"
test -x "$LD/build.sh"

# Upstream's installer retries install steps via sudo when the toolchain prefix
# is system-owned (the current .deb installs under /opt/libdragon).
(
  cd "$LD"
  ./build.sh
)

test -f "$N64_INST/include/n64.mk"
test -f "$N64_INST/mips64-elf/lib/libdragon.a"
test -x "$N64_INST/bin/n64tool"

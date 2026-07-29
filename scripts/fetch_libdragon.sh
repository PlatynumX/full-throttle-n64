#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
LD="$WORK/libdragon"
COMMIT="${LIBDRAGON_COMMIT:-35f85a0797324a5ed0c723203e33ab3c1da94fdd}"

mkdir -p "$WORK"
if [ ! -d "$LD/.git" ]; then
  git clone --filter=blob:none --no-checkout \
    https://github.com/DragonMinded/libdragon.git "$LD"
fi

git -C "$LD" fetch --depth 1 origin "$COMMIT"
git -C "$LD" checkout --detach FETCH_HEAD
git -C "$LD" reset --hard "$COMMIT"
git -C "$LD" clean -fdx

test "$(git -C "$LD" rev-parse HEAD)" = "$COMMIT"
git -C "$LD" rev-parse HEAD

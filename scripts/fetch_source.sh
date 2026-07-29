#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
SCUMMVM="$WORK/scummvm"
TAG="v1.6.0"

mkdir -p "$WORK"
if [ ! -d "$SCUMMVM/.git" ]; then
  git clone --filter=blob:none --branch "$TAG" --depth 1 \
    https://github.com/scummvm/scummvm.git "$SCUMMVM"
fi

git -C "$SCUMMVM" fetch --depth 1 origin tag "$TAG"
git -C "$SCUMMVM" checkout --detach "$TAG"
git -C "$SCUMMVM" reset --hard "$TAG"
git -C "$SCUMMVM" clean -fdx

git -C "$SCUMMVM" rev-parse HEAD

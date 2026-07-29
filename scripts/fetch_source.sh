#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
SCUMMVM="$WORK/scummvm"
TAG="v1.6.0"
PINNED_COMMIT="f75a652bb7c956f145abe881c87b5dbf5c9ec24b"

mkdir -p "$WORK"
if [ ! -d "$SCUMMVM/.git" ]; then
  git clone --filter=blob:none --branch "$TAG" --depth 1 \
    https://github.com/scummvm/scummvm.git "$SCUMMVM"
fi

git -C "$SCUMMVM" fetch --depth 1 origin tag "$TAG"
git -C "$SCUMMVM" checkout --detach "$TAG"
git -C "$SCUMMVM" reset --hard "$TAG"
git -C "$SCUMMVM" clean -fdx

actual="$(git -C "$SCUMMVM" rev-parse HEAD)"
if [ "$actual" != "$PINNED_COMMIT" ]; then
  echo "v1.6.0 resolved to unexpected commit: $actual" >&2
  exit 1
fi
printf '%s\n' "$actual"

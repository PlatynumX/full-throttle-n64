#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="${FT64_REPO_URL:-https://github.com/PlatynumX/full-throttle-n64.git}"
DEST="${HOME}/ft64-r2j-push"

printf '[publish] validating pristine r2j tree\n'
bash "$ROOT/scripts/preflight.sh"

printf '[publish] fresh-cloning %s\n' "$REPO_URL"
rm -rf "$DEST"
git clone "$REPO_URL" "$DEST"

printf '[publish] replacing tracked project tree while preserving fresh .git\n'
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
(
  cd "$ROOT"
  tar \
    --exclude='./.git' \
    --exclude='./work' \
    --exclude='./artifacts' \
    --exclude='./demo-cache' \
    -cf - .
) | tar -xf - -C "$DEST"

cd "$DEST"
printf '[publish] validating exact tree that will be committed\n'
bash ./scripts/preflight.sh

git add -A
git diff --cached --check

if git diff --cached --quiet; then
  echo '[publish] remote already matches r2j; nothing to commit.'
  exit 0
fi

git commit -m 'Full Throttle N64 r2j clean backend baseline'
# Race-safe without ever force pushing. Actions has contents:read and cannot move master.
git fetch origin master
git rebase origin/master
git push origin master

echo '[publish] r2j pushed successfully.'

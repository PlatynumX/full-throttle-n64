# Full Throttle N64 r2e — Termux update

Keep the project in Termux home, not Android shared storage.

```bash
cd ~
rm -rf ~/full-throttle-n64-r2e
unzip -o ~/storage/downloads/full-throttle-n64-r2e.zip -d ~
cd ~/full-throttle-n64-r2e
bash ./scripts/preflight.sh
```

To update the existing GitHub repository without force-pushing:

```bash
cd ~/full-throttle-n64-r2e
rm -rf .git
git init
git remote add origin https://github.com/PlatynumX/full-throttle-n64.git
git fetch origin master
git checkout -b master origin/master

git add -A
git commit -m "Full Throttle N64 r2e CI compatibility fixes"
git push origin master
```

If Git reports that your configured default branch is not `master`, stop and use
that branch name instead; do not force-push.

Run manually if needed:

```bash
gh workflow run build-full-throttle-r2e.yml
gh run watch
```

## Recommended r2e publish path

Keep this extracted r2e directory out of Git and publish it through a fresh clone:

```bash
cd ~/full-throttle-n64-r2e
bash ./scripts/publish_termux.sh
```

The publisher validates the pristine source tree, clones the current GitHub repository,
overlays r2e **without copying `.git`**, validates the exact tree again, runs
`git diff --cached --check`, rebases on the current remote tip, and then pushes.

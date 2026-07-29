# Full Throttle N64 r2f — Termux update

Keep the project in Termux home, not Android shared storage.

```bash
cd ~
rm -rf ~/full-throttle-n64-r2f
unzip -o ~/storage/downloads/full-throttle-n64-r2f.zip -d ~
cd ~/full-throttle-n64-r2f
bash ./scripts/preflight.sh
```

To update the existing GitHub repository without force-pushing:

```bash
cd ~/full-throttle-n64-r2f
rm -rf .git
git init
git remote add origin https://github.com/PlatynumX/full-throttle-n64.git
git fetch origin master
git checkout -b master origin/master

git add -A
git commit -m "Full Throttle N64 r2f CI compatibility fixes"
git push origin master
```

If Git reports that your configured default branch is not `master`, stop and use
that branch name instead; do not force-push.

Run manually if needed:

```bash
gh workflow run build-full-throttle-r2f.yml
gh run watch
```

## Recommended r2f publish path

Keep this extracted r2f directory out of Git and publish it through a fresh clone:

```bash
cd ~/full-throttle-n64-r2f
bash ./scripts/publish_termux.sh
```

The publisher validates the pristine source tree, clones the current GitHub repository,
overlays r2f **without copying `.git`**, validates the exact tree again, runs
`git diff --cached --check`, rebases on the current remote tip, and then pushes.

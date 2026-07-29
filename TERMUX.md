# Full Throttle N64 r2b — Termux update

Keep the project in Termux home, not Android shared storage.

```bash
cd ~
rm -rf ~/full-throttle-n64-r2b
unzip -o ~/storage/downloads/full-throttle-n64-r2b.zip -d ~
cd ~/full-throttle-n64-r2b
bash ./scripts/preflight.sh
```

To update the existing GitHub repository without force-pushing:

```bash
cd ~/full-throttle-n64-r2b
rm -rf .git
git init
git remote add origin https://github.com/PlatynumX/full-throttle-n64.git
git fetch origin master
git checkout -b master origin/master

git add -A
git commit -m "Full Throttle N64 r2b native libdragon filesystem"
git push origin master
```

If Git reports that your configured default branch is not `master`, stop and use
that branch name instead; do not force-push.

Run manually if needed:

```bash
gh workflow run build-full-throttle-r2b.yml
gh run watch
```

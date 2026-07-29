<<<<<<< HEAD
# Full Throttle N64 r2b — Termux update
=======
# Full Throttle N64 r2c — Termux update
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)

Keep the project in Termux home, not Android shared storage.

```bash
cd ~
<<<<<<< HEAD
rm -rf ~/full-throttle-n64-r2b
unzip -o ~/storage/downloads/full-throttle-n64-r2b.zip -d ~
cd ~/full-throttle-n64-r2b
=======
rm -rf ~/full-throttle-n64-r2c
unzip -o ~/storage/downloads/full-throttle-n64-r2c.zip -d ~
cd ~/full-throttle-n64-r2c
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
bash ./scripts/preflight.sh
```

To update the existing GitHub repository without force-pushing:

```bash
<<<<<<< HEAD
cd ~/full-throttle-n64-r2b
=======
cd ~/full-throttle-n64-r2c
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
rm -rf .git
git init
git remote add origin https://github.com/PlatynumX/full-throttle-n64.git
git fetch origin master
git checkout -b master origin/master

git add -A
<<<<<<< HEAD
git commit -m "Full Throttle N64 r2b native libdragon filesystem"
=======
git commit -m "Full Throttle N64 r2c CI compatibility fixes"
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
git push origin master
```

If Git reports that your configured default branch is not `master`, stop and use
that branch name instead; do not force-push.

Run manually if needed:

```bash
<<<<<<< HEAD
gh workflow run build-full-throttle-r2b.yml
=======
gh workflow run build-full-throttle-r2c.yml
>>>>>>> 5fed4cf (Full Throttle N64 r2c CI compatibility fixes)
gh run watch
```

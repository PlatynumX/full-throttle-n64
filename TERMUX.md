# Termux upload/build commands

After downloading `full-throttle-n64-r2a.zip`, extract it directly into Termux home so Android shared-storage permissions cannot interfere:

```bash
cd ~
rm -rf full-throttle-n64-r2a
unzip -o ~/storage/downloads/full-throttle-n64-r2a.zip -d ~
cd ~/full-throttle-n64-r2a
bash ./scripts/preflight.sh
```

## Update the GitHub repository you already created for r2

Reuse its Git metadata instead of creating a second repository:

```bash
cd ~
rm -rf ~/full-throttle-n64-r2a/.git
cp -a ~/full-throttle-n64-r2/.git ~/full-throttle-n64-r2a/.git
cd ~/full-throttle-n64-r2a
git status
git add -A
git commit -m "Full Throttle N64 r2a Android-safe CI invocation"
git push
```

The push triggers **Build Full Throttle N64 r2a** automatically. You can also run it manually from GitHub Actions.

The artifact is named:

```text
full-throttle-n64-r2a-build-report
```

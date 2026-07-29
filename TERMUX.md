# Full Throttle N64 r2l — Termux

Keep the extracted project in Termux home, not Android shared storage.

```bash
cd ~
rm -rf ~/full-throttle-n64-r2l
unzip -o ~/storage/downloads/full-throttle-n64-r2l.zip -d ~
cd ~/full-throttle-n64-r2l
bash ./scripts/preflight.sh
bash ./scripts/publish_termux.sh
```

`publish_termux.sh` is the supported publish path. It:

1. validates the extracted r2l tree;
2. fresh-clones the current GitHub repository;
3. replaces the project contents without copying any `.git` directory;
4. validates the exact tree to be committed;
5. runs `git diff --cached --check`;
6. commits, rebases on the current remote tip, and pushes without force-pushing.

The push triggers `build-full-throttle-r2l.yml` automatically.

To manually start or watch the workflow:

```bash
gh workflow run build-full-throttle-r2l.yml
gh run watch
```

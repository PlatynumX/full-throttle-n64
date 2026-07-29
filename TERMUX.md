# Full Throttle N64 r2o — Termux

After downloading `full-throttle-n64-r2o.zip`:

```bash
cd ~

rm -rf ~/full-throttle-n64-r2o
unzip -o ~/storage/downloads/full-throttle-n64-r2o.zip -d ~

cd ~/full-throttle-n64-r2o

bash ./scripts/preflight.sh
bash ./scripts/publish_termux.sh
```

`publish_termux.sh` fresh-clones the current GitHub repository, overlays r2o
without copying any `.git` directory, validates the exact tree, runs
`git diff --cached --check`, rebases on the current remote `master`, and pushes.

The push triggers `build-full-throttle-r2o.yml`.

The repository no longer fetches or packages Full Throttle game/demo data.
Keep the files already on the SummerCart at `sd:/fullthrottle/`.

# Full Throttle N64 r2m — Termux

After downloading `full-throttle-n64-r2m.zip`:

```bash
cd ~

rm -rf ~/full-throttle-n64-r2m
unzip -o ~/storage/downloads/full-throttle-n64-r2m.zip -d ~

cd ~/full-throttle-n64-r2m

bash ./scripts/preflight.sh
bash ./scripts/publish_termux.sh
```

`publish_termux.sh` fresh-clones the current GitHub repository, overlays r2m
without copying any `.git` directory, validates the exact tree, runs
`git diff --cached --check`, rebases on the current remote `master`, and pushes.

The push triggers `build-full-throttle-r2m.yml`.

The repository no longer fetches or packages Full Throttle game/demo data.
Keep the files already on the SummerCart at `sd:/fullthrottle/`.

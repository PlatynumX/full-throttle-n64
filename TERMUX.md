# Full Throttle N64 r2o — Termux

After downloading a full `full-throttle-n64-r2o.zip` project package:

```bash
cd ~
rm -rf ~/full-throttle-n64-r2o
unzip -o ~/storage/downloads/full-throttle-n64-r2o.zip -d ~
cd ~/full-throttle-n64-r2o
bash ./scripts/preflight.sh
bash ./scripts/publish_termux.sh
```

`scripts/publish_termux.sh` fresh-clones the GitHub repository, replaces the
tracked project tree with the validated r2o tree, runs preflight again on the
exact commit candidate, runs `git diff --cached --check`, refuses to silently
rebase onto a moving remote, and pushes only when the remote base is unchanged.

The push triggers `build-full-throttle-r2o.yml`.

The repository does not fetch or package Full Throttle game/demo data. Keep the
existing files on the SummerCart at `sd:/fullthrottle/`.

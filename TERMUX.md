# Termux upload/build commands

After downloading `full-throttle-n64-r2.zip`:

```bash
cd ~/storage/downloads
unzip -o full-throttle-n64-r2.zip
cd full-throttle-n64-r2
chmod +x scripts/*.sh
./scripts/preflight.sh
```

To create a GitHub repository and push it with GitHub CLI:

```bash
pkg install -y git gh
git init
git add .
git commit -m "Full Throttle N64 r2 libdragon backend"
gh auth status || gh auth login
gh repo create full-throttle-n64 --public --source=. --remote=origin --push
```

If the repository already exists:

```bash
git init
git branch -M main
git add .
git commit -m "Full Throttle N64 r2 libdragon backend"
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/YOURNAME/full-throttle-n64.git
git push -u origin main
```

Then open **Actions → Build Full Throttle N64 r2 → Run workflow**.

The artifact is named:

```text
full-throttle-n64-r2-build-report
```

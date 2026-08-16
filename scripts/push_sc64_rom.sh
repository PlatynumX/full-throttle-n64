#!/data/data/com.termux/files/usr/bin/bash
set -u

ROM="${1:-}"
if [ -z "$ROM" ] || [ ! -f "$ROM" ]; then
    echo "[sc64-push] ROM not found: $ROM" >&2
    exit 2
fi

UPLOADER="${FT64_SC64_UPLOADER:-}"
if [ -n "$UPLOADER" ]; then
    if [ ! -x "$UPLOADER" ] && ! command -v "$UPLOADER" >/dev/null 2>&1; then
        echo "[sc64-push] FT64_SC64_UPLOADER is not executable: $UPLOADER" >&2
        exit 3
    fi
elif [ -x "$HOME/sc64-termux-log/sc64-upload" ]; then
    UPLOADER="$HOME/sc64-termux-log/sc64-upload"
elif command -v sc64deployer >/dev/null 2>&1; then
    UPLOADER="$(command -v sc64deployer)"
elif [ -x "$HOME/sc64-termux-log/sc64deployer" ]; then
    UPLOADER="$HOME/sc64-termux-log/sc64deployer"
else
    echo "[sc64-push] ROM ready, but no write-capable SummerCart uploader is installed."
    echo "[sc64-push] Existing sc64-listen is read-only and cannot upload."
    echo "[sc64-push] ROM: $ROM"
    echo "[sc64-push] Set FT64_SC64_UPLOADER=/path/to/uploader when available."
    exit 4
fi

echo "[sc64-push] uploader: $UPLOADER"
echo "[sc64-push] ROM:      $ROM"

if [ "$(basename "$UPLOADER")" = "sc64deployer" ]; then
    "$UPLOADER" upload "$ROM"
else
    "$UPLOADER" "$ROM"
fi

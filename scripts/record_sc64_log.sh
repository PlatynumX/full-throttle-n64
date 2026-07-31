#!/usr/bin/env bash
set -euo pipefail

LISTENER="${FT64_SC64_LISTENER:-$HOME/sc64-termux-log/sc64-listen}"
OUTDIR="${FT64_LOG_DIR:-$HOME/storage/downloads}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$OUTDIR/ft64-sc64-$STAMP.log"

mkdir -p "$OUTDIR"

if [ ! -e "$LISTENER" ]; then
    echo "SummerCart listener not found: $LISTENER" >&2
    echo "Set FT64_SC64_LISTENER=/path/to/sc64-listen if yours is elsewhere." >&2
    exit 1
fi
if [ ! -x "$LISTENER" ]; then
    echo "SummerCart listener exists but is not executable: $LISTENER" >&2
    exit 1
fi

echo "Full Throttle N64 r2u SummerCart capture"
echo "Listener: $LISTENER"
echo "Log:      $LOG"
if [ "$#" -gt 0 ]; then
    echo "USB arg:  $*"
else
    echo "USB arg:  auto/default"
fi
echo "Reproduce the crash or black screen, wait 3-5 seconds if the logger remains connected, then press Ctrl+C."
echo

set +e
"$LISTENER" "$@" 2>&1 | tee -a "$LOG"
status=${PIPESTATUS[0]}
set -e

echo
echo "Capture stopped. Log saved to:"
echo "$LOG"

# Ctrl+C commonly returns 130 and is a normal way to finish a capture.
if [ "$status" -ne 0 ] && [ "$status" -ne 130 ]; then
    exit "$status"
fi

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
PORT="$SCUMMVM/backends/platform/n64libdragon"
ART="$ROOT/artifacts"
ROM="full-throttle-n64-r2u.z64"
mkdir -p "$ART"

set +e
make -C "$PORT" clean
make -C "$PORT" V=1 -j"$(nproc)" 2>&1 | tee "$ART/scummvm-build.log"
rc=${PIPESTATUS[0]}
set -e

ELF="$PORT/build/full-throttle-n64-r2u.elf"

if [ "$rc" -eq 0 ] && [ -f "$PORT/$ROM" ] && [ -f "$ELF" ]; then
    cp "$PORT/$ROM" "$ART/$ROM"
    cp "$ELF" "$ART/full-throttle-n64-r2u.elf"
    sha256sum "$ART/$ROM" > "$ART/full-throttle-n64-r2u.sha256"
    sha256sum "$ART/full-throttle-n64-r2u.elf" > "$ART/full-throttle-n64-r2u-elf.sha256"

    mips64-elf-size "$ELF" > "$ART/r2u-elf-size.txt"
    mips64-elf-size -A "$ELF" > "$ART/r2u-elf-sections.txt"
    mips64-elf-readelf -S -W "$ELF" > "$ART/r2u-elf-readelf-sections.txt"
    mips64-elf-readelf -l -W "$ELF" > "$ART/r2u-elf-readelf-segments.txt"
    mips64-elf-objdump -h "$ELF" > "$ART/r2u-elf-objdump-sections.txt"
    mips64-elf-nm -S -n --defined-only "$ELF" > "$ART/r2u-elf-symbols-by-address.txt"
    mips64-elf-nm -S --size-sort --defined-only "$ELF" > "$ART/r2u-elf-symbols-by-size.txt"
    tail -n 400 "$ART/r2u-elf-symbols-by-size.txt" > "$ART/r2u-largest-400-symbols.txt"

    {
        echo "Physical target RAM with Expansion Pak: 8388608"
        echo "Runtime heap total is reported by [FT64DIAG r2u] MEM/HB/NEW lines."
        echo
        cat "$ART/r2u-elf-size.txt"
    } > "$ART/r2u-static-memory-summary.txt"

    printf 'PASS\n' > "$ART/scummvm-build-status.txt"
else
    fail_rc="$rc"
    if [ "$fail_rc" -eq 0 ]; then
        # A successful make without the declared ROM is still a failed build.
        fail_rc=1
    fi
    printf 'FAIL rc=%s\n' "$fail_rc" > "$ART/scummvm-build-status.txt"
    exit "$fail_rc"
fi

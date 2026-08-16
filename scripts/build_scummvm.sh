#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCUMMVM="$ROOT/work/scummvm"
PORT="$SCUMMVM/backends/platform/n64libdragon"
ART="$ROOT/artifacts"
ROM="full-throttle-n64-r2v-v19.z64"
mkdir -p "$ART"

set +e
make -C "$PORT" clean
make -C "$PORT" V=1 -j"$(nproc)" 2>&1 | tee "$ART/scummvm-build.log"
rc=${PIPESTATUS[0]}
set -e

ELF="$PORT/build/full-throttle-n64-r2v-v19.elf"

if [ "$rc" -eq 0 ] && [ -f "$PORT/$ROM" ] && [ -f "$ELF" ]; then
    cp "$PORT/$ROM" "$ART/$ROM"
    cp "$ELF" "$ART/full-throttle-n64-r2v-v19.elf"
    sha256sum "$ART/$ROM" > "$ART/full-throttle-n64-r2v-v19.sha256"
    sha256sum "$ART/full-throttle-n64-r2v-v19.elf" > "$ART/full-throttle-n64-r2v-v19-elf.sha256"

    mips64-elf-size "$ELF" > "$ART/r2v-elf-size.txt"
    mips64-elf-size -A "$ELF" > "$ART/r2v-elf-sections.txt"
    mips64-elf-readelf -S -W "$ELF" > "$ART/r2v-elf-readelf-sections.txt"
    mips64-elf-readelf -l -W "$ELF" > "$ART/r2v-elf-readelf-segments.txt"
    mips64-elf-objdump -h "$ELF" > "$ART/r2v-elf-objdump-sections.txt"
    mips64-elf-nm -S -n --defined-only "$ELF" > "$ART/r2v-elf-symbols-by-address.txt"
    mips64-elf-nm -S --size-sort --defined-only "$ELF" > "$ART/r2v-elf-symbols-by-size.txt"
    mips64-elf-nm -C -S -n --defined-only "$ELF" > "$ART/r2v-elf-symbols-demangled-by-address.txt"
    mips64-elf-nm -C -S --size-sort --defined-only "$ELF" > "$ART/r2v-elf-symbols-demangled-by-size.txt"
    tail -n 400 "$ART/r2v-elf-symbols-by-size.txt" > "$ART/r2v-largest-400-symbols.txt"

    MAP="$PORT/build/full-throttle-n64-r2v-v19.map"
    if [ -f "$MAP" ]; then
        cp "$MAP" "$ART/full-throttle-n64-r2v-v19.map"
    fi

    baseline_static=3836317
    current_static="$(awk 'NR==2 {print $4}' "$ART/r2v-elf-size.txt")"
    static_saved=$((baseline_static - current_static))
    backend_heap_saved=153600
    total_expected_headroom=$((static_saved + backend_heap_saved))
    {
        echo "r2u static baseline: $baseline_static"
        echo "r2v static image: $current_static"
        echo "static bytes saved: $static_saved"
        echo "double-buffer heap bytes saved: $backend_heap_saved"
        echo "combined expected headroom gain: $total_expected_headroom"
    } > "$ART/r2v-size-comparison.txt"

    {
        for pattern in \
            'Scumm::ScummDebugger' \
            'Scumm::Player_SID' \
            'Scumm::Player_NES' \
            'Scumm::Player_PCE' \
            'Scumm::Player_Towns' \
            'Scumm::ScummEngine_v8' \
            'Scumm::ScummEngine_v0' \
            'GUI::LauncherDialog' \
            'MusicManager'; do
            count="$(grep -Fc "$pattern" "$ART/r2v-elf-symbols-demangled-by-address.txt" || true)"
            printf '%s: %s\n' "$pattern" "$count"
        done
    } > "$ART/r2v-pruned-symbol-audit.txt"

    {
        echo "Physical target RAM with Expansion Pak: 8388608"
        echo "Runtime heap total is reported by [FT64DIAG r2v] MEM/HB/NEW lines."
        echo
        cat "$ART/r2v-elf-size.txt"
    } > "$ART/r2v-static-memory-summary.txt"

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

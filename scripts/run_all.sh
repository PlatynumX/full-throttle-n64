#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p artifacts
./scripts/preflight.sh
./scripts/fetch_source.sh | tee artifacts/scummvm-source.txt
./scripts/fetch_libdragon.sh | tee artifacts/libdragon-source.txt
./scripts/fetch_demo.sh
./scripts/stage_demo_sd.sh
./scripts/integrate_backend.sh
./scripts/build_libdragon.sh
./scripts/build_probe.sh
./scripts/build_scummvm.sh

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p artifacts
bash ./scripts/preflight.sh
bash ./scripts/fetch_source.sh | tee artifacts/scummvm-source.txt
bash ./scripts/fetch_libdragon.sh | tee artifacts/libdragon-source.txt
bash ./scripts/fetch_demo.sh
bash ./scripts/stage_demo_sd.sh
bash ./scripts/integrate_backend.sh
bash ./scripts/build_libdragon.sh
bash ./scripts/build_probe.sh
bash ./scripts/build_scummvm.sh

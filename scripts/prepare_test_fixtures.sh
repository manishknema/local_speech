#!/usr/bin/env bash
set -euo pipefail

ARGS=()
if [[ "${1:-}" == "--skip-download" ]]; then
  ARGS+=("--skip-download")
fi
if [[ "${2:-}" == "--skip-convert" ]]; then
  ARGS+=("--skip-convert")
fi

python3 scripts/prepare_test_fixtures.py "${ARGS[@]}"


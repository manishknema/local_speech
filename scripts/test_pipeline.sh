#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-0}"
SKIP_CONVERT="${SKIP_CONVERT:-0}"
SKIP_NOISY="${SKIP_NOISY:-0}"
ENSURE_MODELS="${ENSURE_MODELS:-0}"
RUN_ANALYZE="${RUN_ANALYZE:-0}"
RUN_TESTS="${RUN_TESTS:-0}"
RUN_BUILD="${RUN_BUILD:-0}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

echo "[pipeline] verifying prerequisites..."
need_cmd python3
need_cmd ffmpeg
if [[ "$SKIP_DOWNLOAD" != "1" ]]; then
  need_cmd yt-dlp
fi

PREP_ARGS=()
if [[ "$SKIP_DOWNLOAD" == "1" ]]; then PREP_ARGS+=("--skip-download"); fi
if [[ "$SKIP_CONVERT" == "1" ]]; then PREP_ARGS+=("--skip-convert"); fi

echo "[pipeline] preparing base fixtures..."
python3 scripts/prepare_test_fixtures.py "${PREP_ARGS[@]}"

if [[ "$SKIP_NOISY" != "1" ]]; then
  echo "[pipeline] generating noisy SNR variants..."
  python3 scripts/generate_noisy_variants.py
fi

if [[ "$ENSURE_MODELS" == "1" ]]; then
  echo "[pipeline] ensuring models in assets/models..."
  python3 scripts/ensure_models_assets.py
fi

echo "[pipeline] validating output structure..."
test -f test_fixtures/fixtures_manifest.json
test -f test_fixtures/paths.template.json
test -f test_fixtures/wav16k/en_clean.wav
test -f test_fixtures/wav16k/hi_clean.wav
test -f test_fixtures/wav16k/code_switch_en_hi.wav
test -f test_fixtures/wav16k/noise_fan.wav
test -f test_fixtures/wav16k/music_bg.wav
test -f test_fixtures/wav16k/silence.wav

if [[ "$RUN_ANALYZE" == "1" ]]; then
  echo "[pipeline] running flutter analyze..."
  flutter analyze
fi

if [[ "$RUN_TESTS" == "1" ]]; then
  echo "[pipeline] running flutter test..."
  flutter test
fi

if [[ "$RUN_BUILD" == "1" ]]; then
  echo "[pipeline] running platform build..."
  case "${RUNNER_OS:-$(uname -s)}" in
    Windows*|MINGW*|MSYS*|CYGWIN*)
      bash scripts/build_windows_vcvars.sh debug
      bash scripts/build_windows_vcvars.sh release
      ;;
    Linux*)
      flutter build linux --release
      ;;
    Darwin*)
      flutter build macos --release
      ;;
    *)
      echo "Unknown platform for RUN_BUILD=1" >&2
      exit 1
      ;;
  esac
fi

echo "[pipeline] done."

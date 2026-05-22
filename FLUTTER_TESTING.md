# FLUTTER_TESTING.md

## Purpose
Canonical test runbook for VigyanTranscribe across local and CI workflows.

## 1. Prerequisites

### Common
1. Flutter SDK (`3.44.0` target in CI)
2. Python 3.10+
3. FFmpeg
4. yt-dlp

### Windows Build Prerequisite
1. Visual Studio C++ Desktop workload
2. `vcvars64.bat` activation (via `scripts/build_windows_vcvars.sh`)

## 2. Core Pipeline (Shell-Only)

Run from project root:
```bash
bash scripts/test_pipeline.sh
```

## 3. Pipeline Toggles

Environment flags:
1. `SKIP_DOWNLOAD=1`
2. `SKIP_CONVERT=1`
3. `SKIP_NOISY=1`
4. `ENSURE_MODELS=1`
5. `RUN_ANALYZE=1`
6. `RUN_TESTS=1`
7. `RUN_BUILD=1`

Example full run:
```bash
ENSURE_MODELS=1 RUN_ANALYZE=1 RUN_TESTS=1 RUN_BUILD=1 bash scripts/test_pipeline.sh
```

## 4. Fast vs Full Modes

### Fast Mode
Goal: quick confidence for wiring/build.
```bash
SKIP_DOWNLOAD=1 SKIP_NOISY=1 RUN_ANALYZE=1 RUN_TESTS=1 bash scripts/test_pipeline.sh
```

### Full Mode
Goal: model-backed validation.
```bash
ENSURE_MODELS=1 RUN_ANALYZE=1 RUN_TESTS=1 RUN_BUILD=1 bash scripts/test_pipeline.sh
```

## 5. Fixture/Noise Data Contracts

1. Fixture paths: `test_fixtures/paths.template.json`
2. Source config: `test_fixtures/sources.json`
3. Expected labels: `test_fixtures/fixtures_manifest.json`
4. Noise tiers and policy: `NOISE_SIMULATION.md`

## 6. Windows Build Commands (Direct)

```bash
bash scripts/build_windows_vcvars.sh debug
bash scripts/build_windows_vcvars.sh release
```

## 7. CI Alignment

CI uses `.github/workflows/ci.yml` and should mirror local shell pipeline behavior.
`assets/models` is cached by manifest hash for full-mode speed.

## 8. HITL Boundary

Manual testing is tracked separately in `HITL_TESTING.md` and should run only after automated baseline passes.


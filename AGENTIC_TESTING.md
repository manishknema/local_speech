# AGENTIC_TESTING.md

## Purpose
Automate as much of VigyanTranscribe testing as possible across Windows, Linux, and macOS (Android can reuse fixture pipeline later).  
HITL remains separate for final perceptual and device-edge validation.

## Required Components

### Common (All OS)
1. Python 3.10+
2. FFmpeg on `PATH`
3. `yt-dlp` on `PATH`

### Windows
1. Git Bash / MSYS2 Bash (shell entrypoint)
2. Flutter SDK
3. Visual Studio C++ workload (`vcvars64.bat` available for desktop builds)

### Linux
1. Bash
2. Flutter Linux prerequisites

### macOS
1. Bash or zsh
2. Flutter macOS prerequisites (Xcode command line tools)

## Fixture Pipeline (Automated)

### Input Config
- `test_fixtures/sources.json`
  - YouTube IDs
  - clip start offsets
  - output names
  - canonical defaults (`16kHz`, mono, `s16`, 20s)

### Output
1. Raw downloads: `test_fixtures/raw/*.m4a`
2. Canonical clips: `test_fixtures/wav16k/*.wav`
3. Fixture expectations: `test_fixtures/fixtures_manifest.json`
4. Path contract template: `test_fixtures/paths.template.json`

### Commands

#### Windows/Linux/macOS (bash)
```bash
bash scripts/test_pipeline.sh
```

### Optional Build Wrapper (Windows)
```bash
bash scripts/build_windows_vcvars.sh debug
bash scripts/build_windows_vcvars.sh release
```

### Optional Flags
Use environment variables with shell pipeline:
1. `SKIP_DOWNLOAD=1` : use existing raw files
2. `SKIP_CONVERT=1` : skip conversion step
3. `SKIP_NOISY=1` : skip SNR noisy variant generation
4. `RUN_ANALYZE=1` : include `flutter analyze`
5. `RUN_TESTS=1` : include `flutter test`
6. `RUN_BUILD=1` : include platform build step
7. `ENSURE_MODELS=1` : ensure/download required models into `assets/models` before tests

## CI Readiness

## Path Resolution Contract (for test cases)
1. Tests should read `test_fixtures/paths.template.json` first.
2. If present, `test_fixtures/paths.local.json` can override locations per runner.
3. Test discovery should use:
   - raw glob: `test_fixtures/raw/*.m4a`
   - canonical glob: `test_fixtures/wav16k/*.wav`
4. Required canonical baseline files are listed in `paths.template.json`.

## Model Presence Policy (`assets/models`)
1. Models are expected under `assets/models` for full-mode testing.
2. Use:
   - `python3 scripts/ensure_models_assets.py`
   - or `ENSURE_MODELS=1 bash scripts/test_pipeline.sh`
3. For CI speed, cache `assets/models` by manifest hash.

## Minimum CI Steps
1. Install Python, FFmpeg, yt-dlp
2. Run fixture + validation pipeline:
   - `bash scripts/test_pipeline.sh`
3. Run static + tests:
   - `flutter analyze`
   - `flutter test`
4. Build target artifacts per OS

## Windows Build Note for CI
If Windows runner shell does not have C++ env loaded:
```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" && flutter build windows --debug
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" && flutter build windows --release
```

## Automation Scope (What should be automated first)
1. Source-policy switching tests (loopback/hybrid/fallback)
2. Offline VAD/ASR fixture assertions for English-only MVP
3. Speaker embedding stability tests for same-speaker and different-speaker fixtures
4. Offline diarization fixture assertions on complete cached recordings
5. Uncertain-speaker guardrail tests for low-confidence, overlap, noisy, or shorter-than-600ms segments
6. 9-second stall/long-playback regression
7. Model download/install checks
8. Export validation (JSON/SRT)
9. IPC contract checks (`CAPTURE_STATUS`)
10. IST log format checks

## MVP Language Policy
1. LID is not a release blocker for the English-only offline MVP.
2. Language detection tests are diagnostic only until Indic/multilingual ASR is proven.
3. The blocking intelligence tests are speaker identification, offline diarization, and English ASR.

## HITL Separation
See `HITL_TESTING.md` for the manual-only scenarios that remain after automation.

## Model Conversion And Native Wrapper Testing

1. Run Python reference inference first for each model and fixture.
2. Save expected outputs/metrics under a fixture manifest before native conversion.
3. Validate ONNX/CTranslate2/Sherpa output against Python reference.
4. Validate C++/DLL wrapper output against the same reference.
5. Validate Dart IPC/service output against wrapper output.
6. Only then wire the model into the live capture engine.

## Governance And Consent Testing

1. `START_MEETING` without host attestation must be rejected by the engine.
2. `START_MEETING` without announcement confirmation must be rejected by the engine.
3. Late/new speakers must not stop capture; their segments must be `quarantined` and `export_eligible=false`.
4. Marking a speaker `consented` must release prior quarantined segments only when retroactive consent policy is enabled and audit logged.
5. Marking a speaker `denied` or `withdrawn` must redact/exclude prior and future segments by default.
6. Export tests must prove pending/denied/withdrawn speakers are absent or redacted.
7. WhatsApp/share export tests must prove export is explicit and logs included/redacted speaker IDs.

## Hindi/English Workflow Testing

1. ASR tests: English audio -> English text; Hindi candidate audio -> Hindi text where supported.
2. Translation tests: Hindi text -> English/host-language text through IndicTrans2 or configured translation engine.
3. Consent tests: consent phrase transcript + translation is shown to host before marking consented.
4. Combined tests remain blocked until ASR and translation pass independently.

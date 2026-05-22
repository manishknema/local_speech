# RELEASE_CHECKLIST

Date: 2026-05-22  
Owner: Codex  
Purpose: Pre-release quality gate for VigyanTranscribe binaries and runtime behavior.

## How Other Agents Should Use This File

1. Keep section structure identical across OSes.
2. Mark each item with one of:
   - `[ ]` Not run
   - `[~]` In progress
   - `[x]` Pass
   - `[!]` Fail (must include failure note + ticket/commit reference)
3. Add evidence for each major section:
   - command run
   - artifact path
   - log path
   - timestamp (IST)
4. Do not ship if any blocking item is `[ ]`, `[~]`, or `[!]`.
5. Update `session-state.json` with key results and failures.

---

## 1. Windows Release Gate (PRIMARY)

### 1.1 Build Artifacts

- [x] Debug app build succeeds.
- [x] Release app build succeeds.
- [ ] Native DLL debug build succeeds.
- [ ] Native DLL release build succeeds.
- [ ] App loads correct DLL for each mode.

Evidence:
- Command(s): `cmd /c "call ""C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"" && flutter build windows --debug"`, `cmd /c "call ""C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"" && flutter build windows --release"`
- Artifact path(s): `build/windows/x64/runner/Debug/vigyanbytes_transcribe.exe`, `build/windows/x64/runner/Release/vigyanbytes_transcribe.exe`
- Timestamp (IST): 2026-05-22 21:12
- Note: Build shell must load VS developer environment (`vcvars64.bat`) before Flutter Windows builds.

### 1.2 Model Provisioning (Local English First)

- [ ] `whisper-tiny.en` URL reachable.
- [ ] Download completes successfully.
- [ ] Downloaded model file exists at configured path.
- [ ] Model size sanity check passes (non-zero, expected range).
- [ ] Missing model scenario handled with clear UI/backend status.

Evidence:
- URL:
- File path:
- File size:
- Timestamp (IST):

### 1.3 Capture & Ingestion Contract

- [ ] Start capture succeeds from UI.
- [ ] Calibration prompt appears: “Please say one sentence (about 2 seconds)...”
- [ ] Capture status line updates dynamically (`Loopback`, `Hybrid`, `Mic Fallback`, `Unverified`).
- [ ] Stream remains canonical (`16kHz`, mono, float32 contract at adapter boundary).
- [ ] Silence heartbeat maintains pipeline without corrupting frames.

Evidence:
- Backend log path:
- IPC status samples:
- Timestamp (IST):

### 1.4 VAD/LID Stability

- [ ] VAD responds to speech/non-speech transitions.
- [ ] LID returns stable English on known English sample.
- [ ] LID supports rolling-window behavior for code-switch scenarios.
- [ ] No forced-English hack masking model errors.

Evidence:
- Test clip(s):
- Observed outputs:
- Timestamp (IST):

### 1.5 9-Second Stall Regression (Blocking)

- [ ] Continuous playback test (YouTube/system audio) runs for 5+ minutes.
- [ ] No stall around 9 seconds.
- [ ] Dual flush policy observed (silence OR max-duration flush).
- [ ] Engine remains responsive after long non-silent stretches.

Evidence:
- Scenario details:
- Log excerpt refs:
- Timestamp (IST):

### 1.6 Crash/Recovery Behavior

- [ ] No isolate crash on normal run.
- [ ] ONNX input-shape errors are contained and logged.
- [ ] Capture stream error triggers graceful recovery/restart behavior.
- [ ] UI remains connected or reconnects cleanly.

Evidence:
- Error injected:
- Observed recovery:
- Timestamp (IST):

### 1.7 Export Validation

- [ ] JSON export works with valid content.
- [ ] SRT export works with valid timing/text formatting.
- [ ] Export files created at expected directory.

Evidence:
- Export path(s):
- Sample file names:
- Timestamp (IST):

### 1.8 Logging & Observability

- [ ] Backend file logging enabled on Windows.
- [ ] Log timestamps are in IST.
- [ ] Logs include capture start/stop, model status, inference errors, flush events.

Evidence:
- Log file:
- Timestamp format sample:
- Timestamp (IST):

### 1.9 Performance Sanity (Target Hardware)

- [ ] Runs on target high-end Windows hardware profile.
- [ ] Hardware strategy selection logged (oneAPI/SYCL/OpenVINO-first policy, then fallback).
- [ ] UI remains responsive during active capture/inference.

Evidence:
- Hardware summary:
- Selected provider:
- Timestamp (IST):

### 1.10 Final Release Decision (Windows)

- [ ] All blocking sections pass.
- [ ] Release notes updated.
- [ ] Binary signing/packaging (if applicable) completed.
- [ ] Go/No-Go recorded in `session-state.json`.

Decision:
- Release: `NO-GO`
- Owner:
- Timestamp (IST): 2026-05-22 21:13
- Notes: Build artifacts now pass for debug/release. Still blocked by analyze/test failures and pending runtime checklist sections.

---

## 2. macOS Release Gate (Template - TODO)

Status: Not yet populated.

Sections to mirror from Windows:
- Build Artifacts
- Model Provisioning
- Capture & Ingestion Contract
- VAD/LID Stability
- Stall/Recovery Regression
- Export Validation
- Logging & Observability
- Performance Sanity
- Final Release Decision

---

## 3. Linux Release Gate (Template - TODO)

Status: Not yet populated.

Sections to mirror from Windows.

---

## 4. Android Release Gate (Template - TODO / Deferred)

Status: Deferred by roadmap.

Sections to mirror from Windows once Android capture path is active.

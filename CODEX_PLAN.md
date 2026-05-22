# CODEX Plan (Windows-First Recovery)

Date: 2026-05-22
Owner: Codex
Scope: Fast course-correction for Phase 2 with Windows priority.

## 1. Immediate Goals (Next 2 Hours)

1. Stabilize ingestion contract for AI pipeline.
2. Fix MMS-LID reliability by removing format drift.
3. Lock deterministic hardware strategy selection for Windows (oneAPI/SYCL-first path).
4. Keep Indic cloud lane explicitly TODO, non-blocking for Windows local path.

## 2. Architecture Constraints

1. Core pipeline must stay platform-agnostic.
2. Native adapters own all audio math (capture, format conversion, resampling, heartbeat).
3. Signature-first diarization remains source of truth.
4. Continuous heartbeat stream must preserve exact frame contract.

## 3. Execution Plan

## Phase A: Contract Lock

1. Define canonical `AudioFrame`:
   - `Float32`, mono, `16_000 Hz`, fixed frame size.
2. Update `AudioCaptureStrategy` to expose canonical frame stream.
3. Keep legacy bytes stream only as temporary compatibility.

## Phase B: Windows Ingest Correction

1. Ensure WASAPI output converts to canonical frame before VAD/LID.
2. Validate frame invariants per chunk:
   - length, sample rate, channel count, finite range.
3. Preserve heartbeat as valid silent float frames only.

## Phase C: VAD/LID Course Correction

1. Refactor VAD and LID inference to consume canonical frames.
2. Remove hard-coded English bias overrides in LID path.
3. Add rolling-window LID smoothing (2s windows) with confidence gating.
4. Add SBD dual flush:
   - silence threshold
   - max duration timeout.
5. Route-to-Indic contract:
   - send only `header + VAD/LID tags + PCM/WAV chunk`.
   - no raw logits/model internals outside debug mode.

## Phase D: Hardware Strategy

1. Implement hardware strategy abstraction with deterministic provider ordering.
2. Windows policy:
   - prefer oneAPI/SYCL + OpenVINO profile
   - fallback DirectML
   - fallback CPU.
3. macOS/Linux profiles remain abstract with TODO verification hooks.
4. Android stays TODO/open for constrained path.

## 4. Validation Checklist

1. Synthetic audio contract test passes (shape/range/timestamp checks).
2. Real loopback stream keeps pipeline active during silence.
3. VAD no longer sticks in false-noise or false-silence loops.
4. LID produces stable outputs on known English/Hindi clips.
5. No isolate crash from ONNX tensor rank mismatch.

## 5. Deferred Items (Tracked TODO)

1. Vigyan cloud Indic lane integration (`gRPC/WebSocket`) and packaging.
   - payload contract locked: `session metadata + speaker signature + timestamps + audio format + VAD/LID decision + PCM/WAV`.
2. Near-end missing probe and conditional fallback policy.
3. Cross-platform adapter parity for Linux/macOS.
4. Android-specific capture and NPU acceleration strategy.

## 6. Definition of Done (Windows Today)

1. Windows local path runs end-to-end with stable VAD/LID/SBD behavior.
2. Hardware provider selection is explicit and logged.
3. Contract boundary is enforced and no raw-format leakage into AI core.
4. Indic cloud lane remains isolated as TODO without breaking local flow.

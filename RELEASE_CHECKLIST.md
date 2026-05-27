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

### 1.2 Model Provisioning (Offline English First)

- [ ] Sherpa-ONNX offline English ASR model assets are present at configured path.
- [ ] Sherpa-ONNX VAD model asset is present at configured path.
- [ ] Sherpa-ONNX speaker embedding/diarization assets are present at configured path.
- [ ] Model size sanity checks pass (non-zero, expected range).
- [ ] Missing model scenario handled with clear UI/backend status.
- [ ] No cloud model/API dependency is required for MVP transcription.

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

### 1.4 Offline VAD / ASR / Speaker Stability

- [ ] VAD responds to speech/non-speech transitions.
- [ ] English ASR returns usable text on known English sample.
- [ ] Speaker embedding extraction returns stable vectors on known same-speaker samples.
- [ ] Different-speaker samples are not merged above the auto-assign threshold.
- [ ] Offline diarization produces ordered time segments on a complete cached recording.
- [ ] Segments shorter than 600ms are rejected or marked non-identifying.
- [ ] LID is not in the MVP hot path; any language detection remains diagnostic/advisory only.
- [ ] No cloud fallback is used for the MVP English-only offline flow.

Evidence:
- Test clip(s):
- Observed ASR/speaker/diarization outputs:
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
- Offline VAD / ASR / Speaker Stability
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

---

## 5. GOVERNANCE_PRE_REQUISITE (Mandatory, All Platforms)

This is a release blocker for Windows/macOS/Linux/Android whenever meeting audio is captured/transcribed.

### 5.1 Scope and Launch Position

- [ ] Transcription prototype/stabilization may proceed before governance completion.
- [ ] Public release, paid rollout, or enterprise onboarding is blocked until this section is fully `[x]`.
- [ ] Product and policy language avoids claiming "100% DPDP compliant"; approved wording is "DPDP-aligned design pending legal validation."

Evidence:
- Build/release branch:
- Product copy references:
- Timestamp (IST):

### 5.2 Deterministic Consent and Disclosure Controls (No LLM Decisioning)

- [ ] Hard consent gate exists: cannot start recording without host attestation.
- [ ] Hard "Announce Now" gate exists: host must confirm participant disclosure before recording starts.
- [ ] Persistent recording indicator exists while active (`REC`, timer, pause/stop).
- [ ] Participant-change trigger exists (voice-signature drift or explicit host action) and forces re-attestation before continue.
- [ ] Local-only mode is default ON.
- [ ] Cloud fallback (if enabled) requires separate explicit opt-in and separate log events.

Evidence:
- UI screenshots/recordings:
- Guard check location(s):
- Timestamp (IST):

### 5.3 Implementation Contract (Structured Fields)

- [ ] Session log stores:
  `session_id`, `consent_attested`, `consent_attested_at`, `attestation_text_version`,
  `announcement_confirmed`, `announcement_confirmed_at`, `announcement_text_version`,
  `recording_started_at`, `recording_stopped_at`, `participant_reaffirmations[]`,
  `storage_mode`, `export_events[]`, `delete_events[]`.
- [ ] No component infers legal sufficiency from speech content; speech-derived signals are evidence-assist only.

Evidence:
- Schema path:
- Sample session log:
- Timestamp (IST):

### 5.4 Tamper Evidence and Auditability

- [ ] Audit log is append-only.
- [ ] Events include monotonic sequence number + UTC timestamp.
- [ ] Hash-chain or equivalent tamper-evidence is implemented (`prev_hash`, `event_hash` or equivalent).
- [ ] Recording start is rejected if required prior events are missing/out-of-order.
- [ ] Export metadata includes compliance status (`compliant`, `unverified`, `non_compliant`).
- [ ] Speaker-attribution events include confidence, assignment method (`auto`, `manual`, `corrected`, `uncertain`), and reviewer/correction timestamp where applicable.

Evidence:
- Log implementation path:
- Verification command:
- Timestamp (IST):

### 5.5 DPDP-Aligned Product Checklist (India-First)

- [ ] In-app notice clearly states purpose of processing and local-first storage behavior.
- [ ] User can view/trigger deletion of session artifacts (audio/transcript/logs) per retention policy.
- [ ] Retention policy is configurable and enforceable (user/admin).
- [ ] Security controls exist: encryption at rest + access lock (app lock/device auth as applicable).
- [ ] Grievance/support contact is present in privacy surface.
- [ ] Sensitive-use warning exists for medical/legal/professional contexts.
- [ ] Legal copy avoids overclaims; does not present app as a legal authority.

Evidence:
- Policy/version refs:
- Settings paths:
- Timestamp (IST):

### 5.6 How To Implement (Engineering Steps)

- [ ] State machine implemented in shared layer:
  `Idle -> ConsentGate -> AnnounceNow -> Recording -> Paused -> Stopped`.
- [ ] Guard implemented in engine/service layer (not UI only):
  `can_start_recording = consent_attested && announcement_confirmed`.
- [ ] UI prevents bypass from stale state/deep links.
- [ ] Participant-change governance interrupt is tested.
- [ ] Audio identity state machine implemented:
  `Unknown speaker -> Candidate speaker -> Auto-assigned speaker -> Manually confirmed speaker -> Corrected speaker`.
- [ ] Low-confidence, overlap, noisy, or too-short speech is marked `Uncertain Speaker` rather than force-assigned.
- [ ] Enterprise/review workflow can manually assign, merge, or correct speaker labels before final export.
- [ ] Final export distinguishes inferred speaker clusters from legally confirmed participant identities.
- [ ] Unit + integration + regression tests cover bypass attempts.

Evidence:
- Code path(s):
- Test command(s):
- Timestamp (IST):

### 5.7 Release-Blocking Verdict

- [ ] All sections 5.1 through 5.6 are `[x]`.
- [ ] Any `[!]` has linked fix ticket and re-test proof.
- [ ] Go/No-Go entered in `session-state.json`.

Decision:
- Release: `NO-GO` (default until all governance blockers pass)
- Owner:
- Timestamp (IST):
- Notes:

---

## 6. Commercial and Positioning Guardrails (Single Source for Agents)

This section captures the approved go-to-market and legal-positioning model so release decisions and product messaging stay consistent.

### 6.1 Business Priority (Execution Order)

1. Prove offline English transcription works reliably without cloud dependencies.
2. Prove speaker-signature identification and offline diarization reliability.
3. Monetize India-first with strong reliability/price fit.
4. Expand advanced compliance UX and international profiles in staged releases.

### 6.1.1 MVP Runtime Scope

1. MVP hot path is offline-first: canonical audio capture, VAD, speaker embedding/diarization, and English ASR.
2. LID is removed from the MVP hot path because it is not required for English-only offline proof and can introduce false routing.
3. Indic ASR and AI4Bharat/IndicConformer conversion remain research/upgrade work until a Sherpa-compatible ONNX path is proven.
4. Cloud transcription is out of MVP scope unless explicitly enabled in a later release profile.
5. Live speaker labels are provisional unless confidence and/or human confirmation make them final.


### 6.1.2 Hindi/English MVP Workflow Rules

1. MVP audience is India-first but wider-use ready: prove Hindi + English workflow before adding other Indic languages.
2. Capture and transcription remain local-first; no automatic cloud upload is allowed.
3. Host/operator is responsible for lawful consent; VigyanTranscribe provides deterministic consent workflow, audit evidence, and redaction controls.
4. Recording cannot start until host attests responsibility and confirms an announcement/notice was delivered.
5. Late/new speakers do not stop the engine; they are added as `Consent pending` and remain export-ineligible until host confirmation.
6. Speaker identity is probabilistic until confirmed; exports must distinguish inferred speaker clusters from host-confirmed participant identities.
7. Non-consented, denied, withdrawn, or unresolved speaker segments are excluded or redacted from final export by default.
8. Hindi/English consent snippets may be transcribed and translated into the host-selected language for review before marking a speaker consented.
9. IndicTrans2 or equivalent translation is an export/review layer for consented content, not a reason to bypass consent state.
10. WhatsApp/assistant handoff is explicit user-triggered export only; no automatic sending or background sync.
11. Every export records included speakers, redacted speakers, target format/app, translation direction/model, timestamp, and host confirmation.
12. LID is not required for MVP; language handling is driven by selected workflow language and ASR/translation outputs.
### 6.2 Vendor vs Host Responsibility Model

1. VigyanTranscribe is positioned as local-first compliance-assist software.
2. Meeting operator/host is responsible for lawful participant authorization and recording conduct.
3. Product provides controls and audit evidence; it does not provide legal guarantees.
4. Contracts/EULA/terms must match actual data behavior.

### 6.3 Claims Policy (Mandatory)

Allowed phrasing:
1. "Local-first"
2. "On-device by default"
3. "DPDP-aligned design (pending legal validation)"
4. "Compliance-assist workflow"

Disallowed phrasing:
1. "100% DPDP compliant"
2. "Government-certified DPDP compliant"
3. "Legally guaranteed consent verification"
4. "Compliant in all countries by default"

### 6.4 Data Boundary Policy

Current model:
1. Local-only default ON.
2. No automatic cloud sync of transcripts/audio/compliance logs.
3. Manual export only.

If cloud fallback is introduced:
1. Explicit opt-in required.
2. Separate disclosure + logging required.
3. Legal and pricing model must be re-reviewed before rollout.

### 6.5 India-First to International Expansion Rule

1. Launch India-first with English-first runtime proof.
2. Use region compliance profiles before international activation.
3. Do not rely only on IP geolocation; use layered signals.
4. Block unsupported regions until profile + controls are ready.


### 6.6 Model Conversion And Runtime Guardrails

1. Hugging Face Python examples are reference implementations only; production runtime must use task-level Sherpa-ONNX/ONNX Runtime/CTranslate2 wrappers.
2. Every model conversion must document preprocessing, tokenizer/vocab, tensor names, ranks, dynamic axes, decoding, postprocessing, license, and gating status.
3. Python reference, native wrapper, and Dart IPC outputs must be compared on the same fixtures before live-engine use.
4. Models must be selected through a registry/profile so ASR, speaker embedding, diarization, and translation can be swapped independently.
5. IndicTrans2 is text-to-text translation and must not be treated as an audio model or Sherpa speech model.
6. IndicConformer/limited-language Sherpa ASR candidates are experimental until fixture quality, language coverage, and runtime packaging are proven.

### 6.7 Quarantine And Retroactive Consent Policy

1. Pending/unknown speaker segments are stored locally as quarantined and are export-ineligible by default.
2. If a speaker later consents, prior quarantined segments may be released only when `allow_retroactive_consent=true` and an audit event records the release.
3. Enterprise strict mode may disable retroactive consent, making consent effective only from confirmation time forward.
4. Denied or withdrawn speakers are redacted/excluded from prior and future exports by default.
5. Export evidence must include which speakers were included, redacted, pending, denied, or withdrawn.

### 6.8 Future Optimization Track (Post Flutter Transcription Proof)

1. Future IndicConformer 600M conversion belongs to the VVC Docker/NeMo conversion lane, not the current Flutter stabilization lane.
2. Sherpa-ONNX remains the preferred audio runtime only when exported model layouts are Sherpa-compatible.
3. Non-Sherpa ASR exports may be wrapped with a custom native ONNX Runtime `AsrEngine`.
4. IndicTrans2 is a separate text-to-text translation lane using ONNX Runtime or CTranslate2, never Sherpa.
5. Translation isolate must not compete with the audio isolate; thread limits and queueing are required.
6. Translation applies only to consented/export-eligible content by default.
7. This track starts only after capture, PCM, speaker embedding, English ASR, consent ledger, quarantine, and redaction tests pass.

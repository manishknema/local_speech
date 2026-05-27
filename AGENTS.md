# Agent Orchestration & Routing (AGENTS.md)

This is the primary routing layer for all AI entities (Gemini, Claude, Codex, etc.).

## 1. THE MISSION: "VigyanTranscribe" (Flutter Edition)

Build a modular, enterprise-grade meeting transcription app using a decoupled **Flutter** architecture.

- **Frontend**: Flutter UI Isolate (Consumer) - 16pt High-Readability UI.
- **Backend**: OS-specific Audio Engine Isolate (Producer) using a Local IPC boundary.
- **AI Core**: Cross-platform ONNX Runtime (Silero VAD, Meta MMS-LID, WeSpeaker Embedder).
- **Acceleration**: Intel oneAPI SYCL / OpenVINO (Windows), CoreML (Mac), NNAPI (Android).

## 2. HANDOVER ENTRY POINT (IMPORTANT)

We have completed a 12-hour stabilization marathon. To avoid clobbering the stable architecture, ALL agents MUST read:

1.  **[HANDOVER_MANIFEST.md](./handover_manifest.md)**: The definitive technical briefing for the current state.
2.  **[DIAGNOSTICS.md](./DIAGNOSTICS.md)**: Lessons learned regarding WASAPI, byte-alignment, and Isolate crashes.
3.  **[session-state.json](./session-state.json)**: The development biography and Phase 2/3 roadmap.
4.  **[AGENTIC_TESTING.md](./AGENTIC_TESTING.md)**: Cross-platform automation requirements, fixture pipeline, and CI prerequisites.
5.  **[HITL_TESTING.md](./HITL_TESTING.md)**: Manual-only testing policy after automation.
6.  **[FLUTTER_TESTING.md](./FLUTTER_TESTING.md)**: Canonical Flutter testing runbook for local and CI execution.

## 3. Agent-Specific Handover

- **SONNET 3.5 / CODEX**: Pick up from Phase 2 in `session-state.json`. Focus on the **Platform-Agnostic Ingestion Contract** (16kHz Mono Float32 stream).
- **GEMINI**: Refer to the LLD UMLs in `FLUTTER_ARCHITECTURE.md` for Isolate-to-Native bridging.

## 4. Universal Constraints

- **Platform-Agnostic**: Core logic (AI/SBD) must be blind to the OS. Native layers handle all audio math.
- **Signature-First**: 256-d voice vectors are the source of truth for diarization.
- **Native Heartbeat**: Maintain a continuous data stream to the Isolate to prevent UI starvation.

## 5. Documentation Discipline (Mandatory)

Every implementation session MUST update relevant docs before handover:
1. `session-state.json` (timestamped action + outcomes)
2. `FLUTTER_ARCHITECTURE.md` (if architecture/HLD/LLD behavior changes)
3. `FLUTTER_TESTING.md` (if test flow/commands/prerequisites change)
4. `AGENTIC_TESTING.md` / `HITL_TESTING.md` (if automation or manual policy changes)

## 6. Cross-Platform Testing Policy

1. Automation-first across Windows/Linux/macOS via shell pipeline.
2. Windows build path must use vcvars bridge for C++ toolchain activation.
3. Android remains a separate runtime environment; fixture generation is shared and platform-agnostic.
4. HITL is last-mile validation only after automated baseline is green.

## 7. Governance Release Gate (Mandatory)

Governance implementation details and blocking release checks are now centralized in:

- **[RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md)** under `Section 5: GOVERNANCE_PRE_REQUISITE`

All agents must treat that section as mandatory for public release, paid rollout, and enterprise onboarding across all platforms.

---

_Transferred to Sonnet/Codex for Phase 2 Implementation_

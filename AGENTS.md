# Agent Orchestration & Routing (AGENTS.md)

This is the primary routing layer for all AI entities (Gemini, Claude, Codex, etc.). 

## 1. THE MISSION: "TurboTranscribe" (Flutter Edition)
Build a modular, enterprise-grade meeting transcription app using a decoupled **Flutter** architecture. 
- **Frontend**: Flutter UI Isolate (Consumer).
- **Backend**: OS-specific Audio Engine Isolate (Producer) using a Local IPC (WebSocket) boundary.
- **AI Core**: Cross-platform ONNX Runtime (Silero VAD, Meta MMS-LID) for local intelligence.
- **Routing**: English (local) vs. Indic (Vigya Cloud via WAV-header packets).
- **Persistence**: SQLite with future Vector support.

## 2. Context Entry Point
To minimize token usage and maximize alignment, all agents MUST read these two files before any action:
1.  **[session-state.json](./session-state.json)**: Current technical state, dev status, and requirements.
2.  **[LONG_TERM_MEMORY.md](./LONG_TERM_MEMORY.md)**: Project philosophy, architectural history, and durable identity.

## 2. Agent-Specific Instructions
- **GEMINI**: Follow `AGENTS.md` directives for modular backend orchestration and SYCL integration.
- **CLAUDE**: Refer to `CLAUDE.md` for coding style and frontend optimization.
- **CODEX/COPILOT**: Refer to `CODEX.md` for native C++ and SYCL implementation patterns.

## 3. Universal Constraints
- **Signature-First**: Do not deviate to UI-scraping or bots.
- **Discreet Capture**: No features that trigger "Recording" notifications.
- **Modular Pipe**: Maintain separation between Capture, Diarization, and Transcription services.

---
*Generated for Multi-Agent Session Continuity*

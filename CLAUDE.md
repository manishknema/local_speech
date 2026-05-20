# Claude Integration Guide

Claude agents should use this file to align with the project's specialized front-end and system requirements.

## Context Routing
**CRITICAL**: Read [AGENTS.md](./AGENTS.md) first. It points to the core state in `session-state.json`.

## Coding Standards
- **Vanilla Excellence**: Prefer pure HTML/CSS/JS for the dashboard to keep it lightweight.
- **Dumb Display**: The UI should only act as a visualization layer for the data streamed from the Node.js orchestrator.
- **Async Safety**: Ensure all WebSocket message handling is resilient to high-frequency diarization updates.

## Memory
High-level project philosophy is stored in [LONG_TERM_MEMORY.md](./LONG_TERM_MEMORY.md).

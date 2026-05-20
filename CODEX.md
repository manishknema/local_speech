# Codex / Copilot Integration Guide

Codex and Copilot entities should use this file for native C++ and SYCL development standards.

## Context Routing
**CRITICAL**: Read [AGENTS.md](./AGENTS.md) first. It points to the core state in `session-state.json`.

## Technical Standards
- **SYCL Parallelism**: Ensure all voice-embedding extraction is parallelized for GPU/XPU acceleration via Intel oneAPI.
- **Native Addons**: Use `node-addon-api` (N-API) for all C++ integrations to ensure Node.js version compatibility.
- **Buffer Management**: Prioritize zero-copy buffer handling between `naudiodon` and the SYCL diarizer core.

## Memory
High-level project philosophy is stored in [LONG_TERM_MEMORY.md](./LONG_TERM_MEMORY.md).

# Project Long-Term Memory (LTM)

This file is the durable repository for the project's evolution, philosophy, and identity. Unlike `session-state.json`, which tracks transient dev status, this file MUST NOT be purged or overwritten.

## Project Identity & Philosophy
- **Name**: Universal Signature-First Transcription
- **Mission**: To provide 100% discreet, perfectly synchronized, multi-language transcription for meetings and 1-to-1 conversations.
- **Core Principle**: **Voice Signature First.** We identify humans by their mathematical voiceprint, not by scraping names from UIs or using intrusive bots.

## Knowledge Base
- **The "Non-Foolish" Architecture**: We rejected browser-only transcription because it lacks native language depth. We rejected bots because they disclose recording. We chose **OS-Level Loopback + SYCL Diarization**.
- **Hardware Strategy**: Intel oneAPI (SYCL) is our primary target for Windows acceleration to ensure millisecond-level sync.
- **Privacy Policy**: Local-first. Metadata is only discovery-based (UIA/Android Accessibility) or manual.

## Evolutionary History
- **2026-05-18**: Project Initialized. Hybrid model (Web Speech + Node Loopback) established for immediate English meeting readiness. Roadmap for Indic Conformer and SYCL core finalized.
- **2026-05-18**: Decision made to use `session-state.json` for technical state tracking and `AGENTS.md` for multi-agent routing.
- **2026-05-20**: **Strategic Pivot to Flutter**. Abandoned Node.js/FFmpeg architecture due to native compilation fragility. Adopted a decoupled IPC model (UI Isolate <-> Background Isolate) with the Strategy Pattern for OS-agnostic capture. Meta MMS-LID confirmed as the routing layer.

## Future Intent
- Integration with VVC Cloud for Indic Conformer.
- Native Android port utilizing NPU acceleration.
- Secure MCP layer for AI-driven transcript querying.

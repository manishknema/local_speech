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
- **Vigyan Transcribe API Routing (Scenario 2)**: For non-English streams, we do NOT stream raw continuous bits. We use a **3-second floating chunk window** gated by VAD. Upon a 3-second accumulation (or VAD pause), the chunk is evaluated by Meta MMS-LID (INT8 Quantized). We then prepend a **44-byte canonical RIFF WAV header** and package it alongside the **detected language metadata**, sending this standalone `.wav` via WebSocket/gRPC to the backend. **Critically, the Vigyan Web Service transcribes the audio (Indic Conformer) AND translates it using IndicTrans2 (NMT), returning final normalized English text to the local client.** This allows sequence-to-sequence transformer models to find sentence boundaries instantly and ensures the local Action Engine (Gemma) only ever needs to process English prompts.

## Evolutionary History
- **2026-05-18**: Project Initialized. Hybrid model (Web Speech + Node Loopback) established for immediate English meeting readiness. Roadmap for Indic Conformer and SYCL core finalized.
- **2026-05-18**: Decision made to use `session-state.json` for technical state tracking and `AGENTS.md` for multi-agent routing.
- **2026-05-20**: **Strategic Pivot to Flutter**. Abandoned Node.js/FFmpeg architecture due to native compilation fragility. Adopted a decoupled IPC model (UI Isolate <-> Background Isolate) with the Strategy Pattern for OS-agnostic capture. Meta MMS-LID confirmed as the routing layer.

## Future Intent
- Integration with VVC Cloud for Indic Conformer.
- Native Android port utilizing NPU acceleration (Targeting mid-range efficiency, e.g., Samsung M33 5G).
- Secure MCP layer for AI-driven transcript querying.
- **Local Action Execution (Gemma)**: Integration of the **Gemma 2B INT4** model running entirely on-device (via MediaPipe LLM Inference) to parse transcribed commands. Gemma acts purely as an **Intent Parser** (outputting JSON). The actual execution of tasks (e.g., sending an email, setting an alarm) is handled by the Flutter layer converting that JSON into native **Android Intents** (via Platform Channels or packages like `url_launcher`/`android_intent_plus`), meaning the LLM does not need direct system privileges.
- **ONNX Cross-Platform Portability**: The machine learning models themselves (`silero_vad.onnx`, `mms_lid.onnx`) are **100% OS-Agnostic binary files**. They do not require compilation. A single shared artifact repository can serve these exact same `.onnx` files to the Windows client, Android client, and the Linux backend. The only component that changes per OS is the `onnxruntime` execution engine (the `.dll` on Windows, `.so` on Linux/Android), which Flutter/Dart FFI handles automatically during the build process.

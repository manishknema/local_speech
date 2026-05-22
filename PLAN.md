# Implementation Plan: VigyanTranscribe (Flutter Rebuild)

This document serves as the active execution ledger for the Flutter-based decoupled IPC architecture.

## 🏁 Phase 1: Engine Isolation & Data Modeling (CURRENT)
**Goal**: Establish the base interface contracts and the SQLite/IPC foundation.
1. [ ] Scaffold Flutter project structure (**Windows, Android, macOS, Linux, Web**).
2. [ ] Implement `DatabaseRepository` interface & `SqliteVectorRepository`.
3. [ ] Implement `AudioCaptureStrategy` & `OnnxProcessor` abstract interfaces.
4. [ ] Implement the `BackgroundAudioProcessingEngine` Isolate with local WebSocket/HTTP server.

## 🏁 Phase 2: Desktop & Web Functional Parity
**Goal**: Achieve functional parity on all Desktop OSes and verify the HTML/Web dashboard.
1. [ ] Implement `WindowsLoopbackStrategy` via Dart FFI/WASAPI.
2. [ ] Implement `MacosLoopbackStrategy` via CoreAudio hooks.
3. [ ] Implement `LinuxLoopbackStrategy` via ALSA/PulseAudio.
4. [ ] Implement `LocalIpcTranscriptionService` in the UI (Verify connection from **Flutter Web/HTML**).
5. [ ] Setup GitHub Actions/CI for all Desktop targets and Web deployment stubs.

## 🏁 Phase 3: The Intelligence Pipeline
**Goal**: Integrate the VAD/LID logic.
1. [ ] Implement `VadGatekeeper` (Silero ONNX).
2. [ ] Implement `LidClassifier` (Meta MMS-LID).
3. [ ] Implement WAV Packetizer & Cloud Network Emitter.

## 🏁 Phase 4: Android Port
**Goal**: Cross-platform deployment.
1. [ ] Implement `AndroidMicrophoneStrategy` (Platform Channels).
2. [ ] Setup GitHub Actions/CI for Android `.apk` builds.
3. [ ] Optimize for mobile NPUs.

---
*Refer to [session-state.json](./session-state.json) for real-time status updates.*

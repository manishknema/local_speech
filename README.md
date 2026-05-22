# VigyanTranscribe (Universal Transcription)

An enterprise-grade, modular, and cross-platform meeting transcription system built with **Flutter**, **Dart FFI**, and **ONNX Runtime**.

## 🚀 The Vision
VigyanTranscribe provides 100% discreet, perfectly synchronized, multi-language transcription using OS-level loopback (Windows) and MediaProjection (Android). It identifies speakers by their mathematical voice signature and routes audio intelligently between local English models and high-fidelity Indic models on the Vigya Cloud.

## 🏗️ Architecture
The system uses a **Decoupled IPC Model**:
- **Frontend (UI Isolate)**: A clean, responsive Flutter dashboard for live transcripts and speaker tagging.
- **Backend (OS Isolate)**: A high-performance background engine that manages raw PCM capture, Voice Activity Detection (VAD), and Language Identification (LID).
- **Communication**: Separated by a local Inter-Process Communication (IPC) boundary (Local WebSocket/HTTP) to ensure UI fluidity on constrained mobile devices.

For a deep dive into the HLD and LLD, see [**FLUTTER_ARCHITECTURE.md**](./FLUTTER_ARCHITECTURE.md).

## 🛠️ Tech Stack
- **Framework**: Flutter (Cross-platform UI)
- **AI Core**: ONNX Runtime (Local VAD & LID)
- **Transcription**: Local English (Vosk/Whisper) + Remote Indic (IndicConformer)
- **Persistence**: SQLite (Local Database)
- **Hardware**: Optimized for Intel Core Ultra 9 (Laptop) and Mobile NPUs (Android)

## 📦 Getting Started
Follow the [**INSTALLATION.md**](./INSTALLATION.md) guide to set up your local development environment.

## 📖 Roadmap
See [**session-state.json**](./session-state.json) for the current implementation status and phased roadmap.

---
*Building the future of "Non-Foolish" Transcription.*

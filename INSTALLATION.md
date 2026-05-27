# Vigyan Transcribe: Installation & Hardware Requirements

This document details the comprehensive hardware requirements and software prerequisites needed to build and run the Vigyan Transcribe application across all supported platforms.

---

## 💻 Hardware Requirements (Client Side)

The application utilizes a Decoupled IPC Architecture. The heavy processing (Audio Chunking, VAD, LID, and Gemma Action parsing) runs in a background isolate to keep the UI smooth.

### Windows (Primary Desktop Target)
*   **Processor:** Intel Core i5 (8th Gen or newer) or AMD Ryzen equivalent.
    *   *Optimal:* Intel Core Ultra 9 (for SYCL/oneAPI hardware acceleration during diarization).
*   **RAM:** 8 GB minimum (16 GB recommended if running local LLMs).
*   **Storage:** ~250 MB for the application + ONNX models.

### Android (Mobile Target)
*   **Processor:** Mid-range SOC with a dedicated NPU (e.g., Samsung Exynos 1280, Snapdragon 7 Gen 1 or higher).
    *   *Target Benchmark Device:* Samsung Galaxy M33 5G.
*   **RAM:** 6 GB minimum (8 GB highly recommended to support the 2B INT4 quantized Gemma model in memory).
*   **Storage:** ~2 GB (Includes the `.apk`, offline ONNX models, and the ~1.5GB Gemma `.task` file).

### macOS / Linux
*   *Hardware requirements mirror the Windows desktop specifications.*

---

## 📦 Software Prerequisites (Build Environment)

To compile this project from source, you must set up the Flutter SDK and the platform-specific native toolchains.

### 1. Flutter SDK (All Platforms)
*   **Version:** 3.44.0 (Stable Channel).
*   Follow the automated setup scripts in the root directory:
    *   Windows: Run `fix_flutter.bat <path_to_flutter>`
    *   macOS/Linux: Run `./fix_flutter.sh <path_to_flutter>`

### 2. Windows Audio Setup (One-time, before first run)

#### Live Meeting — System Audio Capture (no setup required)
**Live Meeting** captures everything playing through your speakers or headphones — meetings, videos, music — using Windows WASAPI render loopback. This works on every Windows PC regardless of audio chip or driver brand.

**No special configuration is needed.** The app finds your default playback device and taps the render stream directly. If you have multiple playback devices (e.g., speakers and headphones), the app follows whichever is set as the Windows default output.

> **Note:** You do **not** need to enable Stereo Mix, and you should **not** set Stereo Mix as your default recording device. Setting Stereo Mix as default can interfere with microphone detection for In-Person Meetings.

---

#### In-Person Meeting — Microphone Capture
**In-Person Meeting** captures your physical microphone. The app auto-detects the best real hardware microphone on your system using these rules (in order):

| Priority | Device Type | Examples |
|---|---|---|
| **1 (preferred)** | Built-in mic array (FormFactor: Microphone/Headset) | Intel SST Mic Array, laptop built-in mic |
| **2 (fallback)** | USB audio interface (FormFactor: LineLevel) | Focusrite Scarlett, Blue Yeti, HyperX |
| **3 (last resort)** | Windows default recording device | Whatever Windows has selected |

Virtual devices (Stereo Mix, VoiceMeeter, Virtual Cable) are filtered out automatically at all priority levels.

##### Microphone Privacy (required — one-time)
Windows Settings → **Privacy & security** → **Microphone** → turn on **"Let desktop apps access your microphone"**

---

#### Audio Bar Not Moving? Change Device
If the audio bar in the app header shows no signal after starting a meeting:

1. Open the side menu (☰ icon top-left)
2. Tap **Change Device**
3. Select a different device from the list
4. The app restarts audio capture automatically and saves your preference

Your device preference is remembered for future sessions. To go back to auto-detect, open Change Device and select **Auto-detect (default)**.

---

#### Session Recording
Both meeting modes automatically record the session audio to `logs/sessions/session_IST_<timestamp>.wav` (16 kHz, mono, 16-bit PCM) while the meeting runs. The file is finalized when you stop the meeting.

To export the recording to your Documents folder: open the side menu → **Export Session WAV**.

---

### 3. Windows-Specific Toolchain (WASAPI & FFI)
Because we use native C++ to capture system loopback audio via WASAPI, you **must** have the Microsoft C++ build tools installed.
*   **Visual Studio 2022 or 2026** (Community edition is fine).
*   During installation, select the **Desktop development with C++** workload.
*   Ensure the **Windows 10/11 SDK** and **CMake tools for Windows** are checked.

### 3. Android-Specific Toolchain (Mobile Cross-Compilation)
To compile the Android `.apk` locally:
*   **Android Studio:** Latest version (e.g., Ladybug/Baklava).
*   **Android SDK:** API Level 34, 35, or 36 (Baklava).
*   **NDK (Side-by-side):** Required to compile the C++ bindings for ONNX Runtime and SQLite FFI. Install this via the Android Studio SDK Manager.

---

## 🚀 Build Instructions

Once prerequisites are met, fetch the Dart dependencies:
```bash
flutter pub get
```

### Building for Windows
The CMake configuration automatically compiles `windows/runner/audio/loopback_capture.cpp` and links the required `ole32` and `mmdevapi` libraries.
```bash
flutter build windows --release
```

### Building for Android
*Ensure your Android device is connected or an emulator is running.*
```bash
flutter build apk --release
```

---

## 🧠 Model Assets (Post-Install)

The application relies on several AI models to function offline. Place them in `assets/models/` before building.

| File | Size | Purpose |
|---|---|---|
| `silero_vad.onnx` | ~2 MB | Voice Activity Detection — segments speech from silence |
| `mms_lid.onnx` | ~15 MB | Language ID — routes Hindi vs English audio (diagnostic, not in hot path) |
| `speaker_embed.onnx` | ~10 MB | Speaker embeddings for participant identification |
| IndicConformer model files | ~300 MB | Offline Hindi/English ASR via Sherpa-ONNX |

> **IndicConformer note:** The Sherpa-ONNX runtime DLLs are vendored in `assets/runtime/sherpa/windows/`. The model itself must be downloaded separately — see `scripts/ensure_models_assets.py` for the automated download script.

### Sherpa Runtime (Windows)
The Sherpa DLLs (`sherpa-onnx.dll`, `onnxruntime.dll`) are copied to the build output directory automatically by the CMake configuration. No manual DLL placement is needed.

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

### 2. Windows-Specific Toolchain (WASAPI & FFI)
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

The application relies on several AI models to function offline. In a production build, these are bundled into the application assets.

1.  **Silero VAD (ONNX):** ~2 MB. Used for silence stripping and 3-second chunking.
2.  **Meta MMS-LID (ONNX INT8):** ~15 MB. Used for instantaneous language routing.
3.  **Gemma 2B (INT4 Quantized):** ~1.5 GB. Used by MediaPipe for Local Action Execution (Intent Parsing). *(Only loaded if the device meets the 6GB+ RAM requirement).*

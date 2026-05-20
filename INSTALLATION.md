# Installation & Setup (TurboTranscribe Flutter)

This document provides the instructions for setting up the TurboTranscribe development environment on Windows and Android.

## 1. Prerequisites
- **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install) (Stable channel recommended).
- **Dart SDK**: Included with Flutter.
- **Android Studio / VS Code**: With Flutter/Dart plugins installed.
- **Windows Development**: "Desktop development with C++" workload installed via Visual Studio Installer (required for FFI and WASAPI hooks).
- **Android Development**: Android SDK, Command-line tools, and a physical device or emulator.

## 2. Dependency Management
TurboTranscribe uses standard Flutter package management.
```bash
flutter pub get
```

## 3. Platform-Specific Setup

### Windows (Desktop)
The application requires custom C++ FFI bindings for **WASAPI Loopback Capture**.
1. Navigate to `windows/native_audio_capture`.
2. (In Phase 2) Run the provided build script to compile the native DLL.

### Android (Mobile)
Ensure the `AndroidManifest.xml` has the following permissions (implemented in Phase 4):
- `RECORD_AUDIO`
- `FOREGROUND_SERVICE`
- `MEDIA_PROJECTION` (For internal audio capture)

## 4. AI Models (ONNX)
The app uses local ONNX models for VAD and LID.
1. Download the required models (links provided in `assets/models/README.md`).
2. Place them in the `assets/models/` directory.

## 5. Running the App

### Debug Mode
```bash
flutter run -d windows  # For Windows Desktop
flutter run -d android  # For Android Mobile
```

### Release Build
```bash
flutter build windows
flutter build apk
```

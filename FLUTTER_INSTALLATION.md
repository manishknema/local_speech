Here’s the **full unified installation + CI pipeline guide** that covers Windows, macOS, Linux, and also Android builds. This way you can bootstrap Flutter locally and have GitHub Actions produce binaries for all platforms.

---

# FLUTTER_INSTALLATION.md

## 📦 Prerequisites

### Windows

- Windows 10 or 11 (64‑bit)
- [Git for Windows](https://git-scm.com/download/win)
- Visual Studio 2022/2026 with **Desktop development with C++** workload (MSVC, Windows SDK, CMake, Ninja)
- Android Studio (SDK + emulator)
- Chrome (for web builds)

### Windows — Audio Setup (Required)

The app captures system audio via two paths: **microphone** (Media Foundation) and **loopback** (Stereo Mix). Stereo Mix must be manually enabled before loopback capture will work.

**Enable Stereo Mix:**
1. Right-click the speaker icon in the system tray → **Sounds**
2. Go to the **Recording** tab
3. Right-click anywhere in the device list → **Show Disabled Devices**
4. Right-click **Stereo Mix** → **Enable**
5. Click **OK**

Once enabled, the app will automatically detect it and use it for loopback capture via Media Foundation (clean path, full APO chain active).

> **Note:** If Stereo Mix does not appear even after showing disabled devices, your audio driver does not expose it. The app will fall back to raw WASAPI loopback automatically, but audio quality may be lower.

### macOS

- macOS 12 or newer
- Xcode (for iOS/macOS builds)
- Git (preinstalled)
- Android Studio (SDK + emulator)
- Chrome/Safari (for web builds)

### Linux

- Ubuntu/Debian/Fedora (64‑bit)
- Git
- `build-essential` (gcc, g++, make)
- `cmake`, `ninja-build`
- Android Studio (SDK + emulator)
- Chrome/Firefox (for web builds)

---

## 🚀 Installation Steps

1. **Download Flutter SDK (ZIP)**
   - From [flutter.dev/setup](https://flutter.dev/setup) → choose **stable channel**.
   - Extract to your preferred location (e.g. `C:\src\flutter` on Windows, `/opt/flutter` on Linux/macOS).

2. **Add Flutter to PATH**

   **Windows (PowerShell):**

   ```powershell
   setx PATH "%PATH%;C:\src\flutter\bin"
   ```

   **Linux/macOS (bash/zsh):**

   ```bash
   echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. **Fix ZIP Metadata Issue (0.0.0‑unknown)**  
   Run inside your Flutter folder:

   ```bash
   git remote remove origin
   git remote add origin https://github.com/flutter/flutter.git
   git fetch origin --tags --force
   git reset --hard origin/stable
   ```

   Then delete the hidden cache:

   **Windows:**

   ```powershell
   del /f /q bin\cache\.repository_info
   rmdir /s /q bin\cache
   ```

   **Linux/macOS:**

   ```bash
   rm -f bin/cache/.repository_info
   rm -rf bin/cache
   ```

4. **Rebuild Flutter Tool**

   ```bash
   flutter doctor
   flutter upgrade
   ```

5. **Verify**
   ```bash
   flutter --version
   flutter doctor
   ```
   Expected output:
   ```
   Flutter 3.44.0 • channel stable • https://github.com/flutter/flutter.git
   Tools • Dart 3.12.0 • DevTools 2.57.0
   • No issues found!
   ```

---

## 🖥️ Automation Scripts

### Windows (`fix_flutter.bat`)

[fix_flutter.bat](fix_flutter.bat)

Usage:

```bat
fix_flutter.bat C:\src\flutter
```

---

### macOS/Linux (`fix_flutter.sh`)

[fix_flutter.bat](fix_flutter.sh)

Usage:

```bash
chmod +x fix_flutter.sh
./fix_flutter.sh /opt/flutter
```

---

## ⚙️ GitHub CI Pipeline

Create `.github/workflows/flutter-build.yml`:

```yaml
name: Flutter CI

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: "3.44.0"

      - name: Install dependencies
        run: flutter pub get

      - name: Build binaries
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get update && sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev
            flutter build linux --release
          elif [[ "$RUNNER_OS" == "Windows" ]]; then
            flutter build windows --release
          elif [[ "$RUNNER_OS" == "macOS" ]]; then
            flutter build macos --release
          fi

      - name: Build Android APK
        run: flutter build apk --release

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: flutter-${{ matrix.os }}-binary
          path: build/**/release/
```

---

## ✅ Summary

- Local setup documented for Windows/macOS/Linux.
- Scripts fix the `0.0.0-unknown` issue automatically.
- CI pipeline builds **Windows, macOS, Linux binaries** and **Android APKs**.
- Artifacts are uploaded for download from GitHub Actions.

---

👉 With this, you now have a **complete installation + CI automation guide** that works across all platforms and produces binaries for desktop and mobile.

Would you like me to also extend the CI pipeline to **package installers** (e.g., `.msi` for Windows, `.dmg` for macOS, `.deb/.AppImage` for Linux) so you get ready‑to‑ship artifacts instead of raw binaries?

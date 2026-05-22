# Technical Diagnostics: WASAPI & AI Pipeline Failures (Last 12 Hours)

## 1. WASAPI Loopback "Ghost in the Machine"
*   **Symptom:** Garbage LID results (AKA, RON, HUN) and UI Gauge stagnation.
*   **Root Cause:** Improper byte-boundary alignment in the native C++ capture thread. 
*   **Mechanism:** Injected 16-bit zero-integers into a 32-bit float stream, causing bit-shifting corruption. 
*   **Discovery:** The Meta MMS-LID model interpreted the resulting high-energy digital noise as valid speech, leading to random index classifications.

## 2. Sentence Boundary Detection (SBD) Stagnation
*   **Symptom:** Transcripts appeared once at 9 seconds and then never again.
*   **Root Cause:** The 800ms "Absolute Silence" flushing requirement.
*   **Mechanism:** Continuous background noise or music prevented the silence counter from ever hitting the 800ms threshold. The buffer accumulated indefinitely.
*   **Fix Identified:** Implement a 15-second "Auto-Flush" timer and a 2-second rolling window for LID.

## 3. Silent Background Isolate Death
*   **Symptom:** UI stopped updating even with sound playing.
*   **Root Cause:** ONNX Runtime Rank/Dimension mismatch.
*   **Mechanism:** `SpeakerEmbedder` expected `[1, 1, samples]` (Rank 3) but received `[1, samples]` (Rank 2). This threw a C++ exception that bypassed Dart try-catch blocks and terminated the isolate.

## 4. Hardware Acceleration Conflict
*   **Conflict:** Switching between DirectML and OpenVINO without proper DLL cleanup.
*   **Resolution:** Established the `HardwareScanner` factory to deterministically pick SYCL/oneAPI for Intel and DirectML for generic Windows.

## 5. UI Rename Blocking
*   **Symptom:** Changing speaker name caused transcript feed to pause.
*   **Root Cause:** Volatile `TextEditingController` state clobbering the main build loop.
*   **Fix:** Implemented persistent controller maps indexed by Signature ID.

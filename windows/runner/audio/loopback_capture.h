// CRITICAL: No SetClientProperties on any device profile — ever.
// AudioCategory_Communications bypasses the Intel SST APO chain.
// Default audio category = full noise suppression, AGC, DC rejection.
// Device profiles below are TIMING ONLY — they never affect APO routing.
#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <mmreg.h>
#include <cstdint>
#include <functional>
#include <atomic>
#include <thread>
#include <vector>
#include <string>

// Callback type for audio data
typedef void (*AudioDataCallback)(const uint8_t* data, int length);

class LoopbackCapture {
public:
    LoopbackCapture();
    ~LoopbackCapture();

    bool Start(AudioDataCallback callback, bool useMic);
    void Stop();
    bool IsRunning() const { return m_isRunning; }
    const char* GetSelectedDeviceName() const { return m_selectedDeviceNameNarrow.c_str(); }
    void SetPreferredDevice(const std::string& name) { m_preferredDeviceName = name; }

private:
    void CaptureThread();
    bool InitializeAudioClient(bool useMic);
    bool DecodePacketToMonoFloat(const BYTE* data, UINT32 numFrames, DWORD flags, std::vector<float>& monoSamples);
    void ResampleToCanonicalPcm16(const std::vector<float>& inputSamples, std::vector<int16_t>& pcm16Samples);

    std::atomic<bool> m_isRunning;
    std::thread m_captureThread;
    HANDLE m_captureEvent = nullptr;  // signaled by WASAPI when data is ready (EVENTCALLBACK)

    IMMDeviceEnumerator* m_pEnumerator = nullptr;
    IMMDevice* m_pDevice = nullptr;
    IAudioClient* m_pAudioClient = nullptr;
    IAudioCaptureClient* m_pCaptureClient = nullptr;
    WAVEFORMATEX* m_mixFormat = nullptr;

    AudioDataCallback m_dataCallback = nullptr;
    bool m_useMic = false;       // true for both real mic and Stereo Mix (capture endpoint)
    bool m_needsMicGain = false; // true only for real mic (Intel SST delivers low amplitude)
    // m_resampleCursor removed: AUTOCONVERTPCM lets Windows SRC handle 48k→16k.
    double m_resampleCursor = 0.0; // box-average resampler phase accumulator
    std::string m_formatDescription;
    std::string m_selectedDeviceNameNarrow;  // ASCII copy of m_deviceFriendlyName for FFI
    std::string m_preferredDeviceName;       // user override; empty = auto-detect
    int m_loggedPacketStatsCount = 0;

    // Timing parameters only — detected from device friendly name.
    // Intel SST: 20ms buffer + 200ms wake. All others: 100ms + 0ms.
    // These do NOT affect audio category or APO chain.
    REFERENCE_TIME m_bufferDurationRef = 1000000;  // 100ms default (100-ns units)
    int m_wakeDelayMs = 0;
    std::wstring m_deviceFriendlyName;
};

// C-API for Dart FFI
extern "C" {
    __declspec(dllexport) void* Loopback_Create();
    __declspec(dllexport) void Loopback_Destroy(void* instance);
    __declspec(dllexport) bool Loopback_Start(void* instance, AudioDataCallback callback, int useMic);
    __declspec(dllexport) void Loopback_Stop(void* instance);
    __declspec(dllexport) void Audio_FreeBuffer(void* buf);
    // Returns a pointer to the ASCII device name selected by Loopback_Start.
    // Valid until Loopback_Destroy. Never null — returns "" if not yet started.
    __declspec(dllexport) const char* Loopback_GetSelectedDeviceName(void* instance);
    // Returns heap-allocated newline-delimited list of available device names.
    // isMicMode=1 → capture endpoints (mics).  isMicMode=0 → render endpoints (speakers).
    // Caller must free with Audio_FreeBuffer.
    __declspec(dllexport) char* Audio_EnumerateDevices(int isMicMode);
    // Override the auto-selected device for the next Loopback_Start call.
    // Pass the exact name returned by Audio_EnumerateDevices. "" clears override.
    __declspec(dllexport) void Loopback_SetPreferredDevice(void* instance, const char* name);
}

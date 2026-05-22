#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functional>
#include <atomic>
#include <thread>
#include <vector>

// Callback type for audio data
typedef void (*AudioDataCallback)(const uint8_t* data, int length);

class LoopbackCapture {
public:
    LoopbackCapture();
    ~LoopbackCapture();

    bool Start(AudioDataCallback callback, bool useMic);
    void Stop();
    bool IsRunning() const { return m_isRunning; }

private:
    void CaptureThread();
    bool InitializeAudioClient(bool useMic);

    std::atomic<bool> m_isRunning;
    std::thread m_captureThread;
    
    IMMDeviceEnumerator* m_pEnumerator = nullptr;
    IMMDevice* m_pDevice = nullptr;
    IAudioClient* m_pAudioClient = nullptr;
    IAudioCaptureClient* m_pCaptureClient = nullptr;
    
    AudioDataCallback m_dataCallback = nullptr;
};

// C-API for Dart FFI
extern "C" {
    __declspec(dllexport) void* Loopback_Create();
    __declspec(dllexport) void Loopback_Destroy(void* instance);
    __declspec(dllexport) bool Loopback_Start(void* instance, AudioDataCallback callback, int useMic);
    __declspec(dllexport) void Loopback_Stop(void* instance);
}

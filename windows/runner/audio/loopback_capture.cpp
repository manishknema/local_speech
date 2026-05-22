#include "loopback_capture.h"
#include <iostream>
#include <Audiopolicy.h>
#include <vector>

#define REFTIMES_PER_SEC  10000000

#define EXIT_ON_ERROR(hres)  \
              if (FAILED(hres)) { std::cout << "[Native Error] 0x" << std::hex << hres << std::endl; goto Exit; }
#define SAFE_RELEASE(punk)  \
              if ((punk) != NULL)  \
                { (punk)->Release(); (punk) = NULL; }

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
const IID IID_IAudioClient = __uuidof(IAudioClient);
const IID IID_IAudioCaptureClient = __uuidof(IAudioCaptureClient);

LoopbackCapture::LoopbackCapture() : m_isRunning(false) {}

LoopbackCapture::~LoopbackCapture() {
    Stop();
}

bool LoopbackCapture::InitializeAudioClient(bool useMic) {
    HRESULT hr;

    hr = CoInitialize(nullptr);
    if (FAILED(hr)) return false;

    hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL,
        CLSCTX_ALL, IID_IMMDeviceEnumerator,
        (void**)&m_pEnumerator);
    EXIT_ON_ERROR(hr)

    EDataFlow role = useMic ? eCapture : eRender;
    // eMultimedia is significantly more stable for System Loopback
    ERole deviceRole = useMic ? eConsole : eMultimedia;
    
    hr = m_pEnumerator->GetDefaultAudioEndpoint(role, deviceRole, &m_pDevice);
    EXIT_ON_ERROR(hr)

    hr = m_pDevice->Activate(IID_IAudioClient, CLSCTX_ALL, NULL, (void**)&m_pAudioClient);
    EXIT_ON_ERROR(hr)

    WAVEFORMATEX* pwfx;
    hr = m_pAudioClient->GetMixFormat(&pwfx);
    EXIT_ON_ERROR(hr)

    DWORD flags = useMic ? 0 : AUDCLNT_STREAMFLAGS_LOOPBACK;

    hr = m_pAudioClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        flags,
        REFTIMES_PER_SEC,
        0,
        pwfx,
        NULL);
    
    CoTaskMemFree(pwfx);
    EXIT_ON_ERROR(hr)

    hr = m_pAudioClient->GetService(IID_IAudioCaptureClient, (void**)&m_pCaptureClient);
    EXIT_ON_ERROR(hr)

    return true;

Exit:
    SAFE_RELEASE(m_pEnumerator)
    SAFE_RELEASE(m_pDevice)
    SAFE_RELEASE(m_pAudioClient)
    SAFE_RELEASE(m_pCaptureClient)
    return false;
}

bool LoopbackCapture::Start(AudioDataCallback callback, bool useMic) {
    if (m_isRunning) return true;
    m_dataCallback = callback;

    if (!InitializeAudioClient(useMic)) {
        return false;
    }

    m_isRunning = true;
    m_captureThread = std::thread(&LoopbackCapture::CaptureThread, this);
    return true;
}

void LoopbackCapture::Stop() {
    if (m_isRunning) {
        m_isRunning = false;
        if (m_captureThread.joinable()) {
            m_captureThread.join();
        }
    }
    
    SAFE_RELEASE(m_pEnumerator)
    SAFE_RELEASE(m_pDevice)
    SAFE_RELEASE(m_pAudioClient)
    SAFE_RELEASE(m_pCaptureClient)
    CoUninitialize();
}

void LoopbackCapture::CaptureThread() {
    HRESULT hr;
    UINT32 packetLength = 0;
    BYTE* pData;
    UINT32 numFramesAvailable;
    DWORD flags;

    hr = m_pAudioClient->Start();
    if (FAILED(hr)) {
        m_isRunning = false;
        return;
    }

    while (m_isRunning) {
        Sleep(10); 

        hr = m_pCaptureClient->GetNextPacketSize(&packetLength);
        if (FAILED(hr)) break;

        // HEARTBEAT INJECTION: 
        // If system is silent (packetLength == 0), inject dummy zeros to keep the Dart VAD/LID loop alive.
        if (packetLength == 0) {
            std::vector<int16_t> heartbeat(320, 0); // 20ms heartbeat
            if (m_dataCallback) {
                m_dataCallback(reinterpret_cast<uint8_t*>(heartbeat.data()), (uint32_t)(heartbeat.size() * sizeof(int16_t)));
            }
            continue;
        }

        while (packetLength != 0) {
            hr = m_pCaptureClient->GetBuffer(
                &pData,
                &numFramesAvailable,
                &flags,
                NULL,
                NULL);

            if (FAILED(hr)) goto ExitLoop;

            std::vector<int16_t> pcmData;
            pcmData.reserve(numFramesAvailable / 3);

            if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                for (UINT32 i = 0; i < numFramesAvailable; i += 3) {
                    pcmData.push_back(0);
                }
            } else if (pData) {
                float* pFloats = (float*)pData;
                for (UINT32 i = 0; i < numFramesAvailable; i += 3) {
                    float left = pFloats[i * 2];
                    float right = pFloats[i * 2 + 1];
                    float mono = (left + right) / 2.0f;
                    if (mono > 1.0f) mono = 1.0f;
                    if (mono < -1.0f) mono = -1.0f;
                    pcmData.push_back(static_cast<int16_t>(mono * 32767.0f));
                }
            }

            if (m_dataCallback && !pcmData.empty()) {
                m_dataCallback(reinterpret_cast<uint8_t*>(pcmData.data()), (uint32_t)(pcmData.size() * sizeof(int16_t)));
            }

            hr = m_pCaptureClient->ReleaseBuffer(numFramesAvailable);
            if (FAILED(hr)) goto ExitLoop;

            hr = m_pCaptureClient->GetNextPacketSize(&packetLength);
            if (FAILED(hr)) goto ExitLoop;
        }
    }

ExitLoop:
    m_pAudioClient->Stop();
}

void* Loopback_Create() {
    return new LoopbackCapture();
}

void Loopback_Destroy(void* instance) {
    if (instance) {
        delete static_cast<LoopbackCapture*>(instance);
    }
}

bool Loopback_Start(void* instance, AudioDataCallback callback, int useMic) {
    if (instance) {
        return static_cast<LoopbackCapture*>(instance)->Start(callback, useMic != 0);
    }
    return false;
}

void Loopback_Stop(void* instance) {
    if (instance) {
        static_cast<LoopbackCapture*>(instance)->Stop();
    }
}

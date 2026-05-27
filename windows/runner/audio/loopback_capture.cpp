// CRITICAL: No SetClientProperties on any device profile — ever.
// AudioCategory_Communications bypasses the Intel SST APO chain:
// noise suppression, AGC, and DC rejection all stop working.
// Measured result: default category = 40dB SNR (Sound Recorder level).
//                  AudioCategory_Communications = 3.3dB SNR (unusable).
// This rule applies to ALL devices on ALL platforms. See FLUTTER_ARCHITECTURE.md.
#include "loopback_capture.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <Audiopolicy.h>
#include <Functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
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

namespace {
std::string GuidToString(const GUID& guid) {
    std::ostringstream stream;
    stream << std::hex << std::setfill('0')
           << std::setw(8) << guid.Data1 << '-'
           << std::setw(4) << guid.Data2 << '-'
           << std::setw(4) << guid.Data3 << '-'
           << std::setw(2) << static_cast<int>(guid.Data4[0])
           << std::setw(2) << static_cast<int>(guid.Data4[1]) << '-'
           << std::setw(2) << static_cast<int>(guid.Data4[2])
           << std::setw(2) << static_cast<int>(guid.Data4[3])
           << std::setw(2) << static_cast<int>(guid.Data4[4])
           << std::setw(2) << static_cast<int>(guid.Data4[5])
           << std::setw(2) << static_cast<int>(guid.Data4[6])
           << std::setw(2) << static_cast<int>(guid.Data4[7]);
    return stream.str();
}
}  // namespace

LoopbackCapture::LoopbackCapture() : m_isRunning(false) {}

LoopbackCapture::~LoopbackCapture() {
    Stop();
}

bool LoopbackCapture::InitializeAudioClient(bool useMic) {
    HRESULT hr;
    WORD formatTag = 0;
    UINT16 validBits = 0;
    std::string subFormatGuid = "n/a";
    std::string narrowDeviceName;
    IMMDeviceCollection* pCollection = nullptr;
    bool useStereoMixCapture = false;    // set true if Stereo Mix capture device selected
    bool selectedRealHardwareMic = false; // set true when in-person mic is real hardware (not virtual)

    hr = CoInitialize(nullptr);
    if (FAILED(hr)) return false;

    hr = CoCreateInstance(CLSID_MMDeviceEnumerator, NULL,
        CLSCTX_ALL, IID_IMMDeviceEnumerator,
        (void**)&m_pEnumerator);
    EXIT_ON_ERROR(hr)

    // User-preferred device: bypass all auto-detection and find by friendly name.
    if (!m_preferredDeviceName.empty()) {
        const EDataFlow flow = useMic ? eCapture : eRender;
        IMMDeviceCollection* pPrefColl = nullptr;
        if (SUCCEEDED(m_pEnumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &pPrefColl))) {
            UINT count = 0;
            pPrefColl->GetCount(&count);
            for (UINT i = 0; i < count && m_pDevice == nullptr; ++i) {
                IMMDevice* pCand = nullptr;
                IPropertyStore* pPS = nullptr;
                PROPVARIANT varN;
                PropVariantInit(&varN);
                if (SUCCEEDED(pPrefColl->Item(i, &pCand)) &&
                    SUCCEEDED(pCand->OpenPropertyStore(STGM_READ, &pPS)) &&
                    SUCCEEDED(pPS->GetValue(PKEY_Device_FriendlyName, &varN)) &&
                    varN.pwszVal != nullptr) {
                    std::string narrow;
                    for (wchar_t wc : std::wstring(varN.pwszVal)) {
                        narrow += (wc < 128) ? static_cast<char>(wc) : '?';
                    }
                    if (narrow == m_preferredDeviceName) {
                        m_pDevice = pCand;
                        pCand = nullptr;
                        selectedRealHardwareMic = useMic;
                        std::cout << "[Native Audio] Using preferred device: " << narrow << std::endl;
                    }
                }
                PropVariantClear(&varN);
                if (pPS) pPS->Release();
                if (pCand) pCand->Release();
            }
            pPrefColl->Release();
        }
        if (m_pDevice == nullptr) {
            std::cout << "[Native Audio] Preferred device not found, falling back to auto-detect" << std::endl;
        }
    }

    if (m_pDevice == nullptr && useMic) {
        hr = m_pEnumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &pCollection);
        EXIT_ON_ERROR(hr)

        UINT count = 0;
        hr = pCollection->GetCount(&count);
        EXIT_ON_ERROR(hr)

        std::cout << "[Native Audio] Found " << count << " active capture devices" << std::endl;

        // First pass: log all devices.
        for (UINT i = 0; i < count; ++i) {
            IMMDevice* pCandidate = nullptr;
            IPropertyStore* pProps = nullptr;
            PROPVARIANT varName;
            PropVariantInit(&varName);

            if (SUCCEEDED(pCollection->Item(i, &pCandidate)) &&
                SUCCEEDED(pCandidate->OpenPropertyStore(STGM_READ, &pProps)) &&
                SUCCEEDED(pProps->GetValue(PKEY_Device_FriendlyName, &varName))) {
                std::wcout << L"[Native Audio] Capture device[" << i << L"]: "
                           << varName.pwszVal << std::endl;
            }

            PropVariantClear(&varName);
            if (pProps != nullptr) pProps->Release();
            if (pCandidate != nullptr) pCandidate->Release();
        }

        // Second pass: for in-person meeting we need a real hardware microphone.
        // Two-stage search:
        //   Stage 1 — prefer FormFactor Microphone(4)/Headset(5)/Handset(6): WHQL-certified
        //     drivers MUST report this for physical mics. Stereo Mix reports LineLevel(2).
        //   Stage 2 — accept LineLevel(2) if stage 1 finds nothing: catches USB mics and
        //     audio interfaces (Blue Yeti, Focusrite, Behringer) that use generic USB class
        //     drivers and report LineLevel instead of Microphone.
        //   Name guard on both stages: rejects known virtual loopback devices regardless of
        //     FormFactor, for drivers that mis-report (safety net, locale-dependent but
        //     combined with FormFactor covers the vast majority of real-world OEM configs).
        // Fallback: GetDefaultAudioEndpoint if both stages find nothing.
        auto isVirtualDevice = [](const std::wstring& lower) {
            return lower.find(L"stereo mix") != std::wstring::npos ||
                   lower.find(L"wave out mix") != std::wstring::npos ||
                   lower.find(L"what u hear") != std::wstring::npos;
        };

        // Stage 1: definitive hardware mic (FormFactor = Microphone/Headset/Handset).
        for (UINT i = 0; i < count && m_pDevice == nullptr; ++i) {
            IMMDevice* pCandidate = nullptr;
            IPropertyStore* pProps = nullptr;
            PROPVARIANT varFormFactor;
            PROPVARIANT varName;
            PropVariantInit(&varFormFactor);
            PropVariantInit(&varName);

            if (SUCCEEDED(pCollection->Item(i, &pCandidate)) &&
                SUCCEEDED(pCandidate->OpenPropertyStore(STGM_READ, &pProps))) {
                // Stage 1: FormFactor = Microphone(4), Headset(5), or Handset(6).
                bool isRealMic = false;
                if (SUCCEEDED(pProps->GetValue(PKEY_AudioEndpoint_FormFactor, &varFormFactor))) {
                    const UINT ff = varFormFactor.uintVal;
                    isRealMic = (ff == 4 || ff == 5 || ff == 6);
                }
                // Name guard: reject virtual devices even if FormFactor is wrong.
                if (isRealMic && SUCCEEDED(pProps->GetValue(PKEY_Device_FriendlyName, &varName))
                    && varName.pwszVal != nullptr) {
                    std::wstring lower(varName.pwszVal);
                    std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
                    if (isVirtualDevice(lower)) isRealMic = false;
                }

                if (isRealMic) {
                    m_pDevice = pCandidate;
                    pCandidate = nullptr;
                    selectedRealHardwareMic = true;
                }
            }
            PropVariantClear(&varFormFactor);
            PropVariantClear(&varName);
            if (pProps != nullptr) pProps->Release();
            if (pCandidate != nullptr) pCandidate->Release();
        }
        // Stage 2: LineLevel(2) — USB mics and audio interfaces use generic USB class
        // drivers that report LineLevel instead of Microphone. Only reached if Stage 1 found nothing.
        if (m_pDevice == nullptr) {
            for (UINT i = 0; i < count && m_pDevice == nullptr; ++i) {
                IMMDevice* pCandidate = nullptr;
                IPropertyStore* pProps2 = nullptr;
                PROPVARIANT varFF2, varName2;
                PropVariantInit(&varFF2);
                PropVariantInit(&varName2);
                if (SUCCEEDED(pCollection->Item(i, &pCandidate)) &&
                    SUCCEEDED(pCandidate->OpenPropertyStore(STGM_READ, &pProps2))) {
                    bool isLineLevel = false;
                    if (SUCCEEDED(pProps2->GetValue(PKEY_AudioEndpoint_FormFactor, &varFF2))) {
                        isLineLevel = (varFF2.uintVal == 2);  // LineLevel
                    }
                    if (isLineLevel && SUCCEEDED(pProps2->GetValue(PKEY_Device_FriendlyName, &varName2))
                        && varName2.pwszVal != nullptr) {
                        std::wstring lower(varName2.pwszVal);
                        std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
                        if (!isVirtualDevice(lower)) {
                            std::wcout << L"[Native Audio] Stage2 mic (LineLevel): " << varName2.pwszVal << std::endl;
                            m_pDevice = pCandidate;
                            pCandidate = nullptr;
                            selectedRealHardwareMic = true;
                        }
                    }
                }
                PropVariantClear(&varFF2);
                PropVariantClear(&varName2);
                if (pProps2) pProps2->Release();
                if (pCandidate) pCandidate->Release();
            }
        }

        SAFE_RELEASE(pCollection)

        // Fallback: no mic found by FormFactor — use Windows default input device.
        if (m_pDevice == nullptr) {
            std::cout << "[Native Audio] No mic by FormFactor, falling back to Windows default input" << std::endl;
            hr = m_pEnumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &m_pDevice);
            EXIT_ON_ERROR(hr)
        }
    } else if (m_pDevice == nullptr) {
        // Live Meeting: capture whatever is playing through the speakers.
        // OBS approach: use the default render endpoint with AUDCLNT_STREAMFLAGS_LOOPBACK.
        // This works on 100% of Windows Vista+ installations — no Stereo Mix required,
        // no name matching, no OEM dependency. WASAPI loopback on a render endpoint is
        // Windows-native and always available. m_useMic stays false so InitializeAudioClient
        // adds AUDCLNT_STREAMFLAGS_LOOPBACK to the Initialize flags below.
        std::cout << "[Native Audio] Live Meeting: using render loopback (OBS-style)" << std::endl;
        hr = m_pEnumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &m_pDevice);
        EXIT_ON_ERROR(hr)
        // useStereoMixCapture stays false — render endpoint, not a capture endpoint.
    }

    IPropertyStore* pSelectedProps = nullptr;
    PROPVARIANT varSelectedName;
    PropVariantInit(&varSelectedName);
    if (SUCCEEDED(m_pDevice->OpenPropertyStore(STGM_READ, &pSelectedProps)) &&
        SUCCEEDED(pSelectedProps->GetValue(PKEY_Device_FriendlyName, &varSelectedName)) &&
        varSelectedName.pwszVal != nullptr) {
        m_deviceFriendlyName = varSelectedName.pwszVal;
        std::wcout << L"[Native Audio] Selected device: " << m_deviceFriendlyName << std::endl;
    }
    PropVariantClear(&varSelectedName);
    if (pSelectedProps != nullptr) {
        pSelectedProps->Release();
    }

    hr = m_pDevice->Activate(IID_IAudioClient, CLSCTX_ALL, NULL, (void**)&m_pAudioClient);
    EXIT_ON_ERROR(hr)

    WAVEFORMATEX* pwfx = nullptr;
    hr = m_pAudioClient->GetMixFormat(&pwfx);
    EXIT_ON_ERROR(hr)

    m_mixFormat = pwfx;
    m_useMic = useMic || useStereoMixCapture;  // Stereo Mix uses capture path like mic
    m_needsMicGain = selectedRealHardwareMic;  // only real hardware mic (not Stereo Mix/virtual) needs 8x gain
    std::cout << "[Native Audio] needsMicGain=" << m_needsMicGain << std::endl;
    m_resampleCursor = 0.0;
    m_loggedPacketStatsCount = 0;

    formatTag = m_mixFormat->wFormatTag;
    validBits = m_mixFormat->wBitsPerSample;
    if (formatTag == WAVE_FORMAT_EXTENSIBLE &&
        m_mixFormat->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
        const auto* extensible = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(m_mixFormat);
        validBits = extensible->Samples.wValidBitsPerSample != 0
            ? extensible->Samples.wValidBitsPerSample
            : m_mixFormat->wBitsPerSample;
        subFormatGuid = GuidToString(extensible->SubFormat);
        if (IsEqualGUID(extensible->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)) {
            m_formatDescription = "ieee_float";
        } else if (IsEqualGUID(extensible->SubFormat, KSDATAFORMAT_SUBTYPE_PCM)) {
            m_formatDescription = "pcm";
        } else {
            m_formatDescription = "extensible_unknown";
        }
    } else if (formatTag == WAVE_FORMAT_IEEE_FLOAT) {
        m_formatDescription = "ieee_float";
    } else if (formatTag == WAVE_FORMAT_PCM) {
        m_formatDescription = "pcm";
    } else {
        m_formatDescription = "unknown";
    }

    const char* endpointLabel = useMic ? "mic" : (useStereoMixCapture ? "stereo_mix" : "loopback");
    for (wchar_t wc : m_deviceFriendlyName) {
        narrowDeviceName += (wc < 128) ? static_cast<char>(wc) : '?';
    }
    m_selectedDeviceNameNarrow = narrowDeviceName;
    std::cout
        << "[Native Audio] endpoint=" << endpointLabel
        << " device=\"" << narrowDeviceName << "\""
        << " mix=" << m_mixFormat->nSamplesPerSec << "Hz"
        << " channels=" << m_mixFormat->nChannels
        << " bits=" << m_mixFormat->wBitsPerSample
        << " validBits=" << validBits
        << " formatTag=0x" << std::hex << m_mixFormat->wFormatTag << std::dec
        << " subtype=" << m_formatDescription
        << " guid=" << subFormatGuid
        << std::endl;

    // OBS approach: native device format, event-driven, no AUTOCONVERTPCM.
    // AUDCLNT_STREAMFLAGS_EVENTCALLBACK: WASAPI signals m_captureEvent when a
    //   hardware period of data is ready — eliminates Sleep() polling latency.
    // 5-second buffer (BUFFER_TIME_100NS): generous size to prevent overflow
    //   between reads; actual delivery period is still the hardware period (~10ms).
    // No AUTOCONVERTPCM: OBS confirmed this causes SRC artifacts on Intel SST.
    m_captureEvent = CreateEventW(nullptr, false, false, nullptr);
    if (m_captureEvent == nullptr) {
        std::cout << "[Native Error] CreateEventW failed" << std::endl;
        goto Exit;
    }

    {
        constexpr REFERENCE_TIME BUFFER_TIME_100NS = 5LL * 10000000LL;  // 5 seconds
        DWORD flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
        if (!m_useMic) flags |= AUDCLNT_STREAMFLAGS_LOOPBACK;

        hr = m_pAudioClient->Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            flags,
            BUFFER_TIME_100NS,
            0,
            m_mixFormat,
            nullptr);
        EXIT_ON_ERROR(hr)
    }

    hr = m_pAudioClient->SetEventHandle(m_captureEvent);
    EXIT_ON_ERROR(hr)

    hr = m_pAudioClient->GetService(IID_IAudioCaptureClient, (void**)&m_pCaptureClient);
    EXIT_ON_ERROR(hr)

    return true;

Exit:
    SAFE_RELEASE(pCollection)
    if (m_captureEvent != nullptr) {
        CloseHandle(m_captureEvent);
        m_captureEvent = nullptr;
    }
    if (m_mixFormat != nullptr) {
        CoTaskMemFree(m_mixFormat);
        m_mixFormat = nullptr;
    }
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
    if (m_mixFormat != nullptr) {
        CoTaskMemFree(m_mixFormat);
        m_mixFormat = nullptr;
    }
    if (m_captureEvent != nullptr) {
        CloseHandle(m_captureEvent);
        m_captureEvent = nullptr;
    }
    CoUninitialize();
}

bool LoopbackCapture::DecodePacketToMonoFloat(
    const BYTE* data,
    UINT32 numFrames,
    DWORD flags,
    std::vector<float>& monoSamples) {
    monoSamples.clear();

    if (m_mixFormat == nullptr || numFrames == 0) {
        return false;
    }

    const UINT16 channelCount = std::max<UINT16>(1, m_mixFormat->nChannels);
    monoSamples.reserve(numFrames);

    if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
        monoSamples.assign(numFrames, 0.0f);
        return true;
    }

    // Detect sample format from native mix format.
    bool isFloat = false;
    bool isPcm = false;
    UINT16 bitsPerSample = m_mixFormat->wBitsPerSample;

    if (m_mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
        m_mixFormat->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
        const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(m_mixFormat);
        if (IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)) {
            isFloat = true;
        } else if (IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_PCM)) {
            isPcm = true;
        }
    } else if (m_mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) {
        isFloat = true;
    } else if (m_mixFormat->wFormatTag == WAVE_FORMAT_PCM) {
        isPcm = true;
    }

    const UINT32 blockAlign = m_mixFormat->nBlockAlign;
    const UINT16 bytesPerSample = bitsPerSample / 8;

    for (UINT32 i = 0; i < numFrames; ++i) {
        const BYTE* frame = data + static_cast<size_t>(i) * blockAlign;
        double mono = 0.0;

        for (UINT16 ch = 0; ch < channelCount; ++ch) {
            const BYTE* samplePtr = frame + static_cast<size_t>(ch) * bytesPerSample;
            double channelSample = 0.0;

            if (isFloat && bitsPerSample == 32) {
                float f;
                std::memcpy(&f, samplePtr, 4);
                channelSample = static_cast<double>(f);
            } else if (isFloat && bitsPerSample == 64) {
                double d;
                std::memcpy(&d, samplePtr, 8);
                channelSample = d;
            } else if (isPcm && bitsPerSample == 16) {
                int16_t s;
                std::memcpy(&s, samplePtr, 2);
                channelSample = static_cast<double>(s) / 32768.0;
            } else if (isPcm && bitsPerSample == 24) {
                int32_t s = 0;
                std::memcpy(&s, samplePtr, 3);
                if (s & 0x800000) s |= static_cast<int32_t>(0xFF000000);
                channelSample = static_cast<double>(s) / 8388608.0;
            } else if (isPcm && bitsPerSample == 32) {
                int32_t s;
                std::memcpy(&s, samplePtr, 4);
                channelSample = static_cast<double>(s) / 2147483648.0;
            }
            mono += channelSample;
        }

        mono /= channelCount;
        monoSamples.push_back(static_cast<float>(std::clamp(mono, -1.0, 1.0)));
    }

    return true;
}

void LoopbackCapture::ResampleToCanonicalPcm16(
    const std::vector<float>& inputSamples,
    std::vector<int16_t>& pcm16Samples) {
    pcm16Samples.clear();

    if (inputSamples.empty() || m_mixFormat == nullptr) {
        return;
    }

    // Box-average resampler: inputRate → 16kHz.
    // 3-tap FIR (for 48k→16k step=3) — zeros at 16kHz and 32kHz, ~6-13dB stopband.
    const double inputRate = static_cast<double>(m_mixFormat->nSamplesPerSec);
    const double step = inputRate / 16000.0;
    const int filterTaps = static_cast<int>(std::ceil(step));
    const int inputSize = static_cast<int>(inputSamples.size());

    pcm16Samples.reserve(static_cast<int>(std::ceil(inputSize / step)) + 2);

    while (m_resampleCursor < inputSize) {
        const int tapStart = static_cast<int>(m_resampleCursor);
        double sum = 0.0;
        int count = 0;
        for (int t = 0; t < filterTaps && tapStart + t < inputSize; ++t) {
            sum += static_cast<double>(inputSamples[tapStart + t]);
            ++count;
        }
        const double sample = count > 0 ? sum / count : 0.0;

        // Real mic (Intel SST) delivers low amplitude — 8x gain needed.
        // Stereo Mix and render loopback are already full amplitude — no gain.
        const double gained = m_needsMicGain ? sample * 8.0 : sample * 3.0;
        const double gainedClamped = std::clamp(gained, -1.0, 1.0);

        // No DC blocker — proven to cause crackling. Windows APO chain handles DC.
        const double clamped = gainedClamped;
        pcm16Samples.push_back(static_cast<int16_t>(std::lrint(clamped * 32767.0)));

        m_resampleCursor += step;
    }
    m_resampleCursor -= static_cast<double>(inputSamples.size());
    if (m_resampleCursor < 0.0) m_resampleCursor = 0.0;

    if (m_loggedPacketStatsCount < 20) {
        float peak = 0.0f;
        double rms = 0.0;
        for (float s : inputSamples) {
            const float a = std::fabs(s);
            peak = std::max(peak, a);
            rms += static_cast<double>(s) * static_cast<double>(s);
        }
        rms = std::sqrt(rms / static_cast<double>(inputSamples.size()));

        int16_t outPeak = 0;
        for (int16_t s : pcm16Samples) {
            outPeak = std::max<int16_t>(outPeak, static_cast<int16_t>(std::abs(s)));
        }

        std::cout
            << "[Native Audio] packetStats[" << (m_loggedPacketStatsCount + 1) << "]"
            << " src=native(" << static_cast<int>(inputRate) << "Hz)"
            << " inFrames=" << inputSamples.size()
            << " outSamples=" << pcm16Samples.size()
            << " inPeak=" << peak
            << " inRms=" << rms
            << " outPeak=" << outPeak
            << std::endl;
        m_loggedPacketStatsCount++;

        if (peak < 1e-6f) {
            std::cout << "[Native Audio] WARNING: Signal near-zero."
                      << " Check: Windows Settings > Privacy > Microphone"
                      << " > Let desktop apps access microphone = ON"
                      << " OR check physical mic mute button on laptop"
                      << std::endl;
        }
    }
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

    // Intel SST DSP requires time to wake from sleep state after Start().
    // 200ms gives the hardware DSP time to initialise before we read packets.
    Sleep(200);
    m_loggedPacketStatsCount = 0;

    while (m_isRunning) {
        // OBS approach: wait for WASAPI to signal that a hardware period of data is ready.
        // 10ms timeout: fallback for devices where EVENTCALLBACK does not fire reliably
        // during silence (matches OBS legacy thread loopback timeout).
        const DWORD ret = WaitForSingleObject(m_captureEvent, 10);

        if (!m_isRunning) break;

        if (ret == WAIT_TIMEOUT) {
            // No data ready — skip silently.
            // Dart VAD uses stream.listen (event-driven) so absence of data = silence,
            // not a stall. Injecting raw int16 zeros causes sharp discontinuities
            // against real audio samples, producing audible clicks/crackling.
            continue;
        }

        hr = m_pCaptureClient->GetNextPacketSize(&packetLength);
        if (FAILED(hr)) break;

        while (packetLength != 0) {
            hr = m_pCaptureClient->GetBuffer(
                &pData,
                &numFramesAvailable,
                &flags,
                NULL,
                NULL);

            if (FAILED(hr)) goto ExitLoop;

            std::vector<float> monoSamples;
            std::vector<int16_t> pcmData;
            if (!DecodePacketToMonoFloat(pData, numFramesAvailable, flags, monoSamples)) {
                goto ExitLoop;
            }
            ResampleToCanonicalPcm16(monoSamples, pcmData);

            if (m_dataCallback && !pcmData.empty()) {
                // Heap-allocate a persistent copy: NativeCallable.listener is async —
                // it posts only the pointer VALUE to Dart's event queue and returns.
                // The local pcmData vector is destroyed before Dart reads from the pointer,
                // causing use-after-free and crackling. Dart calls Audio_FreeBuffer after copy.
                const int byteLen = static_cast<int>(pcmData.size() * sizeof(int16_t));
                uint8_t* heapBuf = new uint8_t[byteLen];
                std::memcpy(heapBuf, pcmData.data(), byteLen);
                m_dataCallback(heapBuf, byteLen);
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

void Audio_FreeBuffer(void* buf) {
    delete[] static_cast<uint8_t*>(buf);
}

const char* Loopback_GetSelectedDeviceName(void* instance) {
    if (!instance) return "";
    return static_cast<LoopbackCapture*>(instance)->GetSelectedDeviceName();
}

char* Audio_EnumerateDevices(int isMicMode) {
    // Returns newline-delimited ASCII device names, heap-allocated (free with Audio_FreeBuffer).
    std::string result;
    IMMDeviceEnumerator* pEnum = nullptr;
    IMMDeviceCollection* pColl = nullptr;

    CoInitialize(nullptr);
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
                                __uuidof(IMMDeviceEnumerator), (void**)&pEnum))) {
        CoUninitialize();
        char* empty = new char[1]; empty[0] = '\0'; return empty;
    }

    const EDataFlow flow = isMicMode ? eCapture : eRender;
    if (SUCCEEDED(pEnum->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &pColl))) {
        UINT count = 0;
        pColl->GetCount(&count);
        for (UINT i = 0; i < count; ++i) {
            IMMDevice* pDev = nullptr;
            IPropertyStore* pProps = nullptr;
            PROPVARIANT varName;
            PropVariantInit(&varName);
            if (SUCCEEDED(pColl->Item(i, &pDev)) &&
                SUCCEEDED(pDev->OpenPropertyStore(STGM_READ, &pProps)) &&
                SUCCEEDED(pProps->GetValue(PKEY_Device_FriendlyName, &varName)) &&
                varName.pwszVal != nullptr) {
                for (const wchar_t wc : std::wstring(varName.pwszVal)) {
                    result += (wc < 128) ? static_cast<char>(wc) : '?';
                }
                result += '\n';
            }
            PropVariantClear(&varName);
            if (pProps) pProps->Release();
            if (pDev) pDev->Release();
        }
        pColl->Release();
    }
    pEnum->Release();
    CoUninitialize();

    if (!result.empty() && result.back() == '\n') result.pop_back();
    char* buf = new char[result.size() + 1];
    std::memcpy(buf, result.c_str(), result.size() + 1);
    return buf;
}

void Loopback_SetPreferredDevice(void* instance, const char* name) {
    if (!instance) return;
    static_cast<LoopbackCapture*>(instance)->SetPreferredDevice(name ? name : "");
}

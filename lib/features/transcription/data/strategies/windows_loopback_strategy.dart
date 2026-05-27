import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/audio/pcm_codec.dart';
import 'audio_capture_strategy.dart';
import '../../domain/models/audio_frame.dart';

// --- FFI Typedefs ---
typedef AudioDataCallbackC = ffi.Void Function(ffi.Pointer<ffi.Uint8> data, ffi.Int32 length);

typedef LoopbackCreateC = ffi.Pointer Function();
typedef LoopbackCreateDart = ffi.Pointer Function();

typedef LoopbackDestroyC = ffi.Void Function(ffi.Pointer instance);
typedef LoopbackDestroyDart = void Function(ffi.Pointer instance);

typedef LoopbackStartC = ffi.Bool Function(ffi.Pointer instance, ffi.Pointer<ffi.NativeFunction<AudioDataCallbackC>> callback, ffi.Int32 useMic);
typedef LoopbackStartDart = bool Function(ffi.Pointer instance, ffi.Pointer<ffi.NativeFunction<AudioDataCallbackC>> callback, int useMic);

typedef LoopbackStopC = ffi.Void Function(ffi.Pointer instance);
typedef LoopbackStopDart = void Function(ffi.Pointer instance);

typedef AudioFreeBufferC = ffi.Void Function(ffi.Pointer<ffi.Uint8> buf);
typedef AudioFreeBufferDart = void Function(ffi.Pointer<ffi.Uint8> buf);

typedef LoopbackGetDeviceNameC = ffi.Pointer<ffi.Utf8> Function(ffi.Pointer instance);
typedef LoopbackGetDeviceNameDart = ffi.Pointer<ffi.Utf8> Function(ffi.Pointer instance);

typedef AudioEnumerateDevicesC = ffi.Pointer<ffi.Utf8> Function(ffi.Int32 isMicMode);
typedef AudioEnumerateDevicesDart = ffi.Pointer<ffi.Utf8> Function(int isMicMode);

typedef LoopbackSetPreferredDeviceC = ffi.Void Function(ffi.Pointer instance, ffi.Pointer<ffi.Utf8> name);
typedef LoopbackSetPreferredDeviceDart = void Function(ffi.Pointer instance, ffi.Pointer<ffi.Utf8> name);

class WindowsLoopbackStrategy implements AudioCaptureStrategy {
  static const int _vadFrameBytes = 512 * 2;

  late ffi.DynamicLibrary _lib;
  ffi.Pointer? _instance;
  
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>.broadcast();
  final StreamController<AudioFrame> _frameStreamController = StreamController<AudioFrame>.broadcast();
  final BytesBuilder _pendingPcm16 = BytesBuilder(copy: false);
  
  late LoopbackCreateDart _create;
  late LoopbackDestroyDart _destroy;
  late LoopbackStartDart _start;
  late LoopbackStopDart _stop;
  late AudioFreeBufferDart _freeBuffer;
  late LoopbackGetDeviceNameDart _getDeviceName;
  late AudioEnumerateDevicesDart _enumerateDevices;
  late LoopbackSetPreferredDeviceDart _setPreferredDevice;

  ffi.NativeCallable<AudioDataCallbackC>? _nativeCallable;
  bool _useMic = false;
  bool _stopped = false;
  String? _selectedDeviceName;
  String? _preferredDeviceOverride;

  WindowsLoopbackStrategy() {
    if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.executable();
    } else {
      throw UnsupportedError("WindowsLoopbackStrategy is only supported on Windows.");
    }

    _create = _lib.lookupFunction<LoopbackCreateC, LoopbackCreateDart>('Loopback_Create');
    _destroy = _lib.lookupFunction<LoopbackDestroyC, LoopbackDestroyDart>('Loopback_Destroy');
    _start = _lib.lookupFunction<LoopbackStartC, LoopbackStartDart>('Loopback_Start');
    _stop = _lib.lookupFunction<LoopbackStopC, LoopbackStopDart>('Loopback_Stop');
    _freeBuffer = _lib.lookupFunction<AudioFreeBufferC, AudioFreeBufferDart>('Audio_FreeBuffer');
    _getDeviceName = _lib.lookupFunction<LoopbackGetDeviceNameC, LoopbackGetDeviceNameDart>('Loopback_GetSelectedDeviceName');
    _enumerateDevices = _lib.lookupFunction<AudioEnumerateDevicesC, AudioEnumerateDevicesDart>('Audio_EnumerateDevices');
    _setPreferredDevice = _lib.lookupFunction<LoopbackSetPreferredDeviceC, LoopbackSetPreferredDeviceDart>('Loopback_SetPreferredDevice');
  }

  @override
  Stream<Uint8List> get bytesStream => _audioStreamController.stream;

  @override
  Stream<AudioFrame> get frameStream => _frameStreamController.stream;

  @override
  String? get selectedDeviceName => _selectedDeviceName;

  /// Returns the list of available device names for [forMic]=true (capture) or false (render).
  List<String> listAvailableDevices({required bool forMic}) {
    final ptr = _enumerateDevices(forMic ? 1 : 0);
    final raw = ptr.toDartString();
    _freeBuffer(ptr.cast<ffi.Uint8>());
    if (raw.isEmpty) return [];
    return raw.split('\n').where((s) => s.isNotEmpty).toList();
  }

  /// Sets preferred device name for next [startCapture]. Pass null to clear (auto-detect).
  void setPreferredDevice(String? name) {
    _preferredDeviceOverride = name;
  }

  static const _prefKeyMic = 'preferred_mic_device';
  static const _prefKeyLoopback = 'preferred_loopback_device';

  static Future<String?> loadPreferredDevice({required bool forMic}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(forMic ? _prefKeyMic : _prefKeyLoopback);
  }

  static Future<void> savePreferredDevice(String? name, {required bool forMic}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = forMic ? _prefKeyMic : _prefKeyLoopback;
    if (name == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, name);
    }
  }

  @override
  Future<void> startCapture({bool useMic = false}) async {
    if (_instance != null) return;
    
    _useMic = useMic;
    _instance = _create();

    // Apply user-preferred device override before Start, if set.
    final override = _preferredDeviceOverride;
    if (override != null && override.isNotEmpty) {
      final namePtr = override.toNativeUtf8();
      _setPreferredDevice(_instance!, namePtr);
      calloc.free(namePtr);
    }

    // PRODUCTION STABILITY: Use NativeCallable.listener and ensure closure on stop
    _nativeCallable = ffi.NativeCallable<AudioDataCallbackC>.listener(_onAudioDataReceived);
    
    bool success = _start(_instance!, _nativeCallable!.nativeFunction, useMic ? 1 : 0);
    if (!success) {
      _cleanup();
      throw Exception("Failed to start Windows Audio Capture.");
    }
    // Read the device name the C++ selected (pointer to member string — valid until destroy).
    _selectedDeviceName = _getDeviceName(_instance!).toDartString();
  }

  void _onAudioDataReceived(ffi.Pointer<ffi.Uint8> data, int length) {
    // Copy BEFORE freeing: data points to a C++ heap allocation (new uint8_t[]).
    // NativeCallable.listener is async — the C++ local vector is destroyed before
    // this callback runs. C++ heap-allocates and we free here after copy.
    if (length > 0) {
      final copy = Uint8List.fromList(data.asTypedList(length));
      _freeBuffer(data);
      if (_stopped || _nativeCallable == null || _audioStreamController.isClosed) return;
      _pendingPcm16.add(copy);
      _emitBufferedFrames();
    } else {
      _freeBuffer(data);
    }
  }

  void _emitBufferedFrames() {
    final buffered = _pendingPcm16.takeBytes();
    if (buffered.isEmpty) {
      return;
    }

    int offset = 0;
    while (buffered.length - offset >= _vadFrameBytes) {
      final frameBytes = Uint8List.sublistView(
        buffered,
        offset,
        offset + _vadFrameBytes,
      );
      final bytesCopy = Uint8List.fromList(frameBytes);
      _audioStreamController.add(bytesCopy);
      _frameStreamController.add(
        AudioFrame(
          samples: PcmCodec.pcm16LeToFloat32(bytesCopy),
          sampleRateHz: 16000,
          channels: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          source: _useMic ? 'windows_mic' : 'windows_loopback',
        ),
      );
      offset += _vadFrameBytes;
    }

    if (offset < buffered.length) {
      _pendingPcm16.add(Uint8List.sublistView(buffered, offset));
    }
  }

  @override
  Future<void> stopCapture() async {
    _stopped = true; // Guard: reject any in-flight native callbacks immediately
    if (_instance != null) {
      _stop(_instance!);
      _cleanup();
    }
  }

  void _cleanup() {
    _pendingPcm16.clear();
    if (_nativeCallable != null) {
      // CRITICAL: Close before Destroy so the native thread cannot fire after VM shutdown
      _nativeCallable!.close();
      _nativeCallable = null;
    }
    if (_instance != null) {
      _destroy(_instance!);
      _instance = null;
    }
  }
}

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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

class WindowsLoopbackStrategy implements AudioCaptureStrategy {
  late ffi.DynamicLibrary _lib;
  ffi.Pointer? _instance;
  
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>.broadcast();
  final StreamController<AudioFrame> _frameStreamController = StreamController<AudioFrame>.broadcast();
  
  late LoopbackCreateDart _create;
  late LoopbackDestroyDart _destroy;
  late LoopbackStartDart _start;
  late LoopbackStopDart _stop;
  
  ffi.NativeCallable<AudioDataCallbackC>? _nativeCallable;

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
  }

  @override
  Stream<Uint8List> get bytesStream => _audioStreamController.stream;

  @override
  Stream<AudioFrame> get frameStream => _frameStreamController.stream;

  @override
  Future<void> startCapture({bool useMic = false}) async {
    if (_instance != null) return;
    
    _instance = _create();
    
    // PRODUCTION STABILITY: Use NativeCallable.listener and ensure closure on stop
    _nativeCallable = ffi.NativeCallable<AudioDataCallbackC>.listener(_onAudioDataReceived);
    
    bool success = _start(_instance!, _nativeCallable!.nativeFunction, useMic ? 1 : 0);
    if (!success) {
      _cleanup();
      throw Exception("Failed to start Windows Audio Capture.");
    }
  }

  void _onAudioDataReceived(ffi.Pointer<ffi.Uint8> data, int length) {
    if (_nativeCallable == null || _audioStreamController.isClosed) return;
    
    if (length > 0) {
      final bytesCopy = Uint8List.fromList(data.asTypedList(length));
      _audioStreamController.add(bytesCopy);
      _frameStreamController.add(
        AudioFrame(
          samples: _int16BytesToFloat32(bytesCopy),
          sampleRateHz: 16000,
          channels: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          source: 'windows_loopback',
        ),
      );
    }
  }

  Float32List _int16BytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final output = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (int i = 0; i < sampleCount; i++) {
      final s = data.getInt16(i * 2, Endian.little);
      output[i] = s / 32768.0;
    }
    return output;
  }

  @override
  Future<void> stopCapture() async {
    if (_instance != null) {
      _stop(_instance!);
      _cleanup();
    }
  }

  void _cleanup() {
    if (_instance != null) {
      _destroy(_instance!);
      _instance = null;
    }
    if (_nativeCallable != null) {
      // CRITICAL: Close the native callable to prevent GetFfiCallbackMetadata errors on shutdown
      _nativeCallable!.close();
      _nativeCallable = null;
    }
  }
}

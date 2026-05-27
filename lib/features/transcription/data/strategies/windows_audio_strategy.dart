import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'audio_capture_strategy.dart';
import '../../domain/models/audio_frame.dart';
import 'windows_loopback_strategy.dart';

// ARCHITECTURE NOTE:
// The `record` package uses EventChannel for streaming, which is unsupported
// in background isolates (Flutter limitation). Only MethodChannel calls like
// listInputDevices() work. All actual capture goes through WASAPI via FFI
// (WindowsLoopbackStrategy → loopback_capture.cpp).
//
// `record` package here is used solely to enumerate and log input devices,
// which helps diagnose what Windows exposes (Stereo Mix, etc.).
// The C++ layer handles Stereo Mix detection automatically for loopback.

class WindowsAudioStrategy implements AudioCaptureStrategy {
  final AudioRecorder _recorder = AudioRecorder();
  late WindowsLoopbackStrategy _wasapi;

  final StreamController<Uint8List> _bytesController =
      StreamController<Uint8List>.broadcast();
  final StreamController<AudioFrame> _frameController =
      StreamController<AudioFrame>.broadcast();

  StreamSubscription<Uint8List>? _bytesSub;
  StreamSubscription<AudioFrame>? _frameSub;

  @override
  Stream<Uint8List> get bytesStream => _bytesController.stream;

  @override
  Stream<AudioFrame> get frameStream => _frameController.stream;

  @override
  Future<void> startCapture({bool useMic = false}) async {
    // Log all input devices visible to Media Foundation (diagnostic only).
    try {
      final devices = await _recorder.listInputDevices();
      print('[WindowsAudio] ${devices.length} input device(s) found:');
      for (final d in devices) {
        print('[WindowsAudio]   id="${d.id}"  label="${d.label}"');
      }
    } catch (e) {
      print('[WindowsAudio] listInputDevices failed: $e');
    }

    // All capture via WASAPI FFI layer.
    // For loopback (useMic=false): C++ detects Stereo Mix capture device
    //   automatically and prefers it over raw render loopback.
    // For mic (useMic=true): C++ uses default capture device.
    print('[WindowsAudio] Starting WASAPI capture — useMic=$useMic');
    _wasapi = WindowsLoopbackStrategy();
    await _wasapi.startCapture(useMic: useMic);
    _bytesSub = _wasapi.bytesStream.listen(_bytesController.add);
    _frameSub = _wasapi.frameStream.listen(_frameController.add);
  }

  @override
  Future<void> stopCapture() async {
    await _bytesSub?.cancel();
    _bytesSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await _wasapi.stopCapture();
    _bytesController.add(Uint8List(0));
  }
}

import 'dart:async';
import 'dart:typed_data';
import '../../domain/models/audio_frame.dart';

/// Represents a strategy for capturing audio on a specific platform.
abstract class AudioCaptureStrategy {
  /// Legacy stream of PCM bytes (kept for compatibility during Phase 2 migration).
  Stream<Uint8List> get bytesStream;

  /// Canonical stream for AI pipeline: 16kHz mono Float32 frames.
  Stream<AudioFrame> get frameStream;

  /// Initializes and starts the audio capture.
  Future<void> startCapture({bool useMic = false});

  /// Stops the audio capture and releases resources.
  Future<void> stopCapture();

  /// The human-readable name of the device selected during startCapture.
  /// Null until startCapture has been called successfully.
  String? get selectedDeviceName;

  /// Returns available device names for the given mode (mic or loopback).
  List<String> listAvailableDevices({required bool forMic});

  /// Overrides auto-detection for the next startCapture call. Null = auto-detect.
  void setPreferredDevice(String? name);
}

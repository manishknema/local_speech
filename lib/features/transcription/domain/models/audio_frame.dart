import 'dart:typed_data';

/// Canonical platform-agnostic audio frame contract for the AI pipeline.
///
/// All native adapters must normalize to:
/// - mono
/// - 16_000 Hz
/// - Float32 samples in [-1.0, 1.0]
class AudioFrame {
  final Float32List samples;
  final int sampleRateHz;
  final int channels;
  final int timestampMs;
  final String source;

  const AudioFrame({
    required this.samples,
    required this.sampleRateHz,
    required this.channels,
    required this.timestampMs,
    required this.source,
  });
}


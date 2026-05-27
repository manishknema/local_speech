import 'dart:typed_data';

/// PCM helpers for the canonical 16 kHz mono audio boundary.
class PcmCodec {
  const PcmCodec._();

  /// Converts signed little-endian PCM16 bytes to normalized Float32 samples.
  ///
  /// Odd trailing bytes are ignored because they cannot form a complete sample.
  static Float32List pcm16LeToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final output = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);

    for (int i = 0; i < sampleCount; i++) {
      output[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }

    return output;
  }

  /// Converts normalized Float32 samples back to signed PCM16 little-endian bytes.
  static Uint8List float32ToPcm16Le(Float32List samples) {
    final output = Uint8List(samples.length * 2);
    final data = ByteData.sublistView(output);

    for (int i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final scaled = clamped >= 0
          ? (clamped * 32767.0).round()
          : (clamped * 32768.0).round();
      data.setInt16(i * 2, scaled, Endian.little);
    }

    return output;
  }
}

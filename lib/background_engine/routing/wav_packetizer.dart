import 'dart:typed_data';

/// Utility to package raw PCM audio chunks into canonical WAV formats.
/// Used primarily by the Network Emitter before sending non-English audio to the Vigya Cloud.
class WavPacketizer {
  /// Wraps a 16kHz, 16-bit, Mono PCM buffer with a standard 44-byte RIFF WAV header.
  static Uint8List createWavFromPcm(Uint8List pcmData, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
    final int byteRate = (sampleRate * channels * bitsPerSample) ~/ 8;
    final int blockAlign = (channels * bitsPerSample) ~/ 8;
    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;
    
    final header = ByteData(44);
    
    // "RIFF" chunk descriptor
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    
    // "WAVE" format
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    
    // "fmt " sub-chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    
    // "data" sub-chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wavBuffer = BytesBuilder();
    wavBuffer.add(header.buffer.asUint8List());
    wavBuffer.add(pcmData);
    
    return wavBuffer.toBytes();
  }
}

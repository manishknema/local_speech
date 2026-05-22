import 'dart:async';
import 'dart:typed_data';

/// Accumulates raw PCM audio bytes up to a specific time window.
class AudioAccumulator {
  // 16000 samples/sec * 2 bytes/sample (16-bit) = 32000 bytes/sec
  static const int _bytesPerSecond = 32000;
  
  final int targetWindowSeconds;
  final int? fixedChunkBytes;
  final int _maxBytes;
  
  final BytesBuilder _buffer = BytesBuilder();

  AudioAccumulator({this.targetWindowSeconds = 3, this.fixedChunkBytes}) 
      : _maxBytes = fixedChunkBytes ?? (_bytesPerSecond * targetWindowSeconds);

  /// Adds bytes to the accumulator. 
  /// Returns a complete Uint8List chunk if the 3-second window is reached, 
  /// otherwise returns null.
  Uint8List? addBytes(Uint8List incomingBytes) {
    _buffer.add(incomingBytes);

    if (_buffer.length >= _maxBytes) {
      return flush();
    }
    return null;
  }

  /// Forces the accumulator to yield whatever it currently holds and resets.
  /// Used when VAD detects a pause.
  Uint8List? flush() {
    if (_buffer.isEmpty) return null;
    
    final chunk = _buffer.toBytes();
    _buffer.clear();
    return chunk;
  }
  
  void clear() {
    _buffer.clear();
  }
}

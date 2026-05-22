import 'dart:convert';
import 'dart:typed_data';

/// Defines the structure of the payload sent to the Vigyan Cloud.
class CloudTranscriptionPacket {
  /// The detected language ISO code from Meta MMS-LID (e.g., 'hin', 'tam')
  final String detectedLanguage;
  
  /// The 44-byte WAV header + PCM audio bytes.
  final Uint8List wavBytes;

  /// Unique identifier for this chunk (e.g., timestamp)
  final int chunkId;

  CloudTranscriptionPacket({
    required this.detectedLanguage,
    required this.wavBytes,
    required this.chunkId,
  });

  /// Packages the data for WebSocket transmission (if using JSON/Base64 wrapping).
  /// Note: If using pure gRPC, you would map this directly to your Protobuf definition instead.
  String toJsonPayload() {
    return jsonEncode({
      'language': detectedLanguage,
      'chunkId': chunkId,
      'audioBase64': base64Encode(wavBytes),
    });
  }
}

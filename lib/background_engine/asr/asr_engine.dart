import 'dart:typed_data';

enum AsrRuntimeMode { online, segmented }

enum AsrModelTopology { ctc, transducer }

class AsrTranscript {
  final String text;
  final String language;
  final bool translated;
  final String engineId;
  final AsrRuntimeMode runtimeMode;
  final AsrModelTopology topology;

  const AsrTranscript({
    required this.text,
    required this.language,
    required this.engineId,
    required this.runtimeMode,
    required this.topology,
    this.translated = false,
  });
}

abstract class AsrEngine {
  String get engineId;
  AsrRuntimeMode get runtimeMode;
  AsrModelTopology get topology;
  bool get supportsStreaming;

  Future<void> loadModel();
  Future<AsrTranscript> transcribePcm16(Uint8List pcmBytes);
  Future<void> startSession();
  AsrTranscript? ingestSamples(Float32List samples);
  Future<AsrTranscript?> finishSession();
  void dispose();
}

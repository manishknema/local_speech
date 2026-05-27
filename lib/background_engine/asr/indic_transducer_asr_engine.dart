import 'dart:typed_data';

import 'asr_engine.dart';

/// Future IndicConformer lane:
/// - still canonical 16 kHz mono input
/// - online recognizer
/// - transducer topology (encoder/decoder/joiner)
/// - likely LID-gated dynamic model loading to avoid loading all languages at once
class IndicTransducerAsrEngine implements AsrEngine {
  @override
  String get engineId => 'indic_transducer';

  @override
  AsrRuntimeMode get runtimeMode => AsrRuntimeMode.online;

  @override
  AsrModelTopology get topology => AsrModelTopology.transducer;

  @override
  bool get supportsStreaming => false;

  @override
  Future<void> loadModel() async {}

  @override
  Future<void> startSession() async {}

  @override
  AsrTranscript? ingestSamples(Float32List samples) => null;

  @override
  Future<AsrTranscript?> finishSession() async => null;

  @override
  Future<AsrTranscript> transcribePcm16(Uint8List pcmBytes) async {
    final seconds = (pcmBytes.length / 32000.0).toStringAsFixed(1);
    return AsrTranscript(
      text: 'Indic transducer spike buffered about ${seconds}s while language-routed online decode is pending.',
      language: 'indic',
      engineId: engineId,
      runtimeMode: runtimeMode,
      topology: topology,
      translated: false,
    );
  }

  @override
  void dispose() {}
}

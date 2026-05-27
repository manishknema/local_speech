import 'dart:typed_data';

import 'asr_engine.dart';

/// Spike profile for Sherpa-backed Dolphin-style online ASR.
///
/// The live plugin hookup will replace this placeholder once the canonical
/// capture boundary is validated on WASAPI loopback and mic.
class DolphinOnlineAsrEngine implements AsrEngine {
  @override
  String get engineId => 'dolphin_online';

  @override
  AsrRuntimeMode get runtimeMode => AsrRuntimeMode.online;

  @override
  AsrModelTopology get topology => AsrModelTopology.ctc;

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
      text: 'Dolphin online spike heard about ${seconds}s of speech.',
      language: 'auto',
      engineId: engineId,
      runtimeMode: runtimeMode,
      topology: topology,
    );
  }

  @override
  void dispose() {}
}

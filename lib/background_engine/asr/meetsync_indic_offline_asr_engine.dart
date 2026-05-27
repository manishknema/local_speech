import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/audio/pcm_codec.dart';
import '../../core/platform/sherpa_runtime_locator.dart';
import '../../core/platform/windows_dll_directory.dart';
import 'asr_engine.dart';

class MeetsyncIndicOfflineAsrEngine implements AsrEngine {
  static const _modelFileName = 'model.int8.onnx';
  static const _tokensFileName = 'tokens.txt';

  sherpa.OfflineRecognizer? _recognizer;
  String _modelDir = '';

  @override
  String get engineId => 'meetsync_indic_offline';

  @override
  AsrRuntimeMode get runtimeMode => AsrRuntimeMode.segmented;

  @override
  AsrModelTopology get topology => AsrModelTopology.ctc;

  @override
  bool get supportsStreaming => false;

  @override
  Future<void> loadModel() async {
    _modelDir = _resolveModelDir();
    if (Platform.isWindows) {
      final runtimeDir = SherpaRuntimeLocator.locateWindowsRuntimeDir();
      if (runtimeDir == null) {
        throw Exception('Vendored Sherpa runtime not found under assets/runtime/sherpa/windows');
      }
      setWindowsDllDirectory(runtimeDir);
      sherpa.initBindings(runtimeDir);
    } else {
      sherpa.initBindings();
    }

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
          model: '$_modelDir/$_modelFileName',
        ),
        tokens: '$_modelDir/$_tokensFileName',
        numThreads: 2,
        provider: 'cpu',
        modelingUnit: 'bpe',
        bpeVocab: '$_modelDir/$_tokensFileName',
      ),
      decodingMethod: 'greedy_search',
    );

    _recognizer = sherpa.OfflineRecognizer(config);
  }

  @override
  Future<void> startSession() async {}

  @override
  AsrTranscript? ingestSamples(Float32List samples) => null;

  @override
  Future<AsrTranscript?> finishSession() async => null;

  @override
  Future<AsrTranscript> transcribePcm16(Uint8List pcmBytes) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw Exception('Meetsync offline recognizer not initialized');
    }

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(
        samples: PcmCodec.pcm16LeToFloat32(pcmBytes),
        sampleRate: 16000,
      );
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);

      return AsrTranscript(
        text: result.text.trim(),
        language: result.lang.isNotEmpty ? result.lang : 'indic',
        engineId: engineId,
        runtimeMode: runtimeMode,
        topology: topology,
      );
    } finally {
      stream.free();
    }
  }

  @override
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }

  /// Resolves the indic_conformer model directory from the repo assets tree.
  static String _resolveModelDir() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '${Directory.current.path}/assets/models/indic_conformer',
      '$exeDir/data/flutter_assets/assets/models/indic_conformer',
    ];

    for (final path in candidates) {
      final dir = Directory(path);
      final model = File('$path/$_modelFileName');
      final tokens = File('$path/$_tokensFileName');
      if (dir.existsSync() && model.existsSync() && tokens.existsSync()) {
        return dir.absolute.path.replaceAll('\\', '/');
      }
    }

    throw Exception(
      'IndicConformer model not found. Place model.int8.onnx and tokens.txt '
      'in assets/models/indic_conformer/ inside the repo.',
    );
  }
}

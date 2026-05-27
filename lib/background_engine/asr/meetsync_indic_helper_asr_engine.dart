import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/logging/backend_file_logger.dart';
import '../../core/platform/sherpa_runtime_locator.dart';
import 'asr_engine.dart';
import 'sherpa_helper_client.dart';

class MeetsyncIndicHelperAsrEngine implements AsrEngine {
  static const _modelFileName = 'model.int8.onnx';
  static const _tokensFileName = 'tokens.txt';

  final SherpaHelperClient _client = SherpaHelperClient();

  String _modelDir = '';
  String _runtimeDir = '';

  @override
  String get engineId => 'meetsync_indic_helper';

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
      _runtimeDir = SherpaRuntimeLocator.locateWindowsRuntimeDir() ?? '';
      if (_runtimeDir.isEmpty) {
        throw Exception('Vendored Sherpa runtime not found under assets/runtime/sherpa/windows');
      }
    }

    final modelPath = '$_modelDir/$_modelFileName';
    final tokensPath = '$_modelDir/$_tokensFileName';
    final modelExists = File(modelPath).existsSync();
    final tokensExists = File(tokensPath).existsSync();

    BackendFileLogger.instance.log(
      'Meetsync helper ASR init:\n'
      '  runtimeDir = $_runtimeDir\n'
      '  modelPath  = $modelPath  [${modelExists ? "EXISTS" : "MISSING"}]\n'
      '  tokensPath = $tokensPath  [${tokensExists ? "EXISTS" : "MISSING"}]',
    );

    if (!modelExists) {
      throw Exception('IndicConformer model not found: $modelPath');
    }
    if (!tokensExists) {
      throw Exception('IndicConformer tokens not found: $tokensPath');
    }

    await _client.start(
      runtimeDir: _runtimeDir,
      modelPath: modelPath,
      tokensPath: tokensPath,
    );
    BackendFileLogger.instance.log('Meetsync helper ASR initialized (subprocess ready)');
  }

  @override
  Future<void> startSession() async {}

  @override
  AsrTranscript? ingestSamples(Float32List samples) => null;

  @override
  Future<AsrTranscript?> finishSession() async => null;

  @override
  Future<AsrTranscript> transcribePcm16(Uint8List pcmBytes) async {
    BackendFileLogger.instance.log(
      'Meetsync helper ASR transcribe requested (${pcmBytes.length} bytes)',
    );
    final response = await _client.transcribeSegment(pcmBytes);
    if (!response.ok) {
      throw Exception(response.error ?? 'Sherpa helper ASR failed');
    }

    return AsrTranscript(
      text: response.text.trim(),
      language: response.language,
      engineId: engineId,
      runtimeMode: runtimeMode,
      topology: topology,
    );
  }

  @override
  void dispose() {
    unawaited(_client.stop());
  }

  /// Resolves the indic_conformer model directory from the repo assets tree.
  /// Checks three candidate locations so both `flutter run` (project-relative)
  /// and installed/debug builds (exe-relative flutter_assets) work.
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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/backend_file_logger.dart';
import '../../core/platform/sherpa_runtime_locator.dart';
import 'asr_engine.dart';
import 'sherpa_helper_client.dart';

class MeetsyncIndicHelperAsrEngine implements AsrEngine {
  static const _modelFileName = 'model.int8.onnx';
  static const _tokensFileName = 'tokens.txt';
  static const _modelUrl =
      'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main/model.int8.onnx';
  static const _tokensUrl =
      'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main/tokens.txt';

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
    _modelDir = await _ensureModelFiles();
    if (Platform.isWindows) {
      _runtimeDir = SherpaRuntimeLocator.locateWindowsRuntimeDir() ?? '';
      if (_runtimeDir.isEmpty) {
        throw Exception('Vendored Sherpa runtime not found under assets/runtime/sherpa/windows');
      }
    }

    BackendFileLogger.instance.log(
      'Initializing meetsync helper ASR with runtimeDir=$_runtimeDir modelDir=$_modelDir',
    );
    await _client.start(
      runtimeDir: _runtimeDir,
      modelPath: '$_modelDir/$_modelFileName',
      tokensPath: '$_modelDir/$_tokensFileName',
    );
    BackendFileLogger.instance.log('Meetsync helper ASR initialized');
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

  Future<String> _ensureModelFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/meetsync_indic_conformer');
    if (!modelDir.existsSync()) {
      modelDir.createSync(recursive: true);
    }

    await _downloadIfMissing(File('${modelDir.path}/$_modelFileName'), _modelUrl);
    await _downloadIfMissing(File('${modelDir.path}/$_tokensFileName'), _tokensUrl);

    return modelDir.path.replaceAll('\\', '/');
  }

  Future<void> _downloadIfMissing(File target, String url) async {
    if (target.existsSync() && target.lengthSync() > 0) {
      return;
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download ${target.path} from $url (HTTP ${response.statusCode})',
      );
    }

    await target.writeAsBytes(response.bodyBytes, flush: true);
  }
}

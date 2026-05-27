import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/audio/pcm_codec.dart';
import '../../core/platform/sherpa_runtime_locator.dart';
import '../../core/platform/windows_dll_directory.dart';
import 'asr_engine.dart';

class MeetsyncIndicOfflineAsrEngine implements AsrEngine {
  static const _modelFileName = 'model.int8.onnx';
  static const _tokensFileName = 'tokens.txt';
  static const _modelUrl =
      'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main/model.int8.onnx';
  static const _tokensUrl =
      'https://huggingface.co/meetsync/indic-conformer-onnx-sherpa/resolve/main/tokens.txt';

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
    _modelDir = await _ensureModelFiles();
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

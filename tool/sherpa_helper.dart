import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:vigyanbytes_transcribe/core/audio/pcm_codec.dart';
import 'package:vigyanbytes_transcribe/core/platform/windows_dll_directory.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/sherpa_helper.dart <runtime_dir> <model_path> <tokens_path>',
    );
    exitCode = 64;
    return;
  }

  final runtimeDir = args[0];
  final modelPath = args[1];
  final tokensPath = args[2];

  if (Platform.isWindows) {
    setWindowsDllDirectory(runtimeDir);
    sherpa.initBindings(runtimeDir);
  } else {
    sherpa.initBindings();
  }

  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
          model: modelPath,
        ),
        tokens: tokensPath,
        numThreads: 2,
        provider: 'cpu',
        modelingUnit: 'bpe',
        bpeVocab: tokensPath,
      ),
      decodingMethod: 'greedy_search',
    ),
  );

  stdout.writeln(jsonEncode({'type': 'ready'}));

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) {
      continue;
    }

    Map<String, dynamic> request;
    try {
      request = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      stderr.writeln('Invalid JSON request: $e');
      continue;
    }

    if (request['type'] == 'shutdown') {
      break;
    }

    final id = request['id'] as String?;
    final pcmBase64 = request['pcm16_base64'] as String?;
    if (id == null || pcmBase64 == null) {
      continue;
    }

    try {
      final pcmBytes = base64Decode(pcmBase64);
      final text = _decodeSegment(recognizer, pcmBytes);
      stdout.writeln(jsonEncode({
        'id': id,
        'ok': true,
        'text': text,
        'language': 'indic',
      }));
    } catch (e) {
      stdout.writeln(jsonEncode({
        'id': id,
        'ok': false,
        'error': e.toString(),
      }));
    }
  }

  recognizer.free();
}

String _decodeSegment(sherpa.OfflineRecognizer recognizer, Uint8List pcmBytes) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(
      samples: PcmCodec.pcm16LeToFloat32(pcmBytes),
      sampleRate: 16000,
    );
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    return result.text.trim();
  } finally {
    stream.free();
  }
}

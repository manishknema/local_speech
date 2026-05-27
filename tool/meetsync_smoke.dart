import 'dart:io';
import 'dart:typed_data';
import 'package:vigyanbytes_transcribe/core/audio/pcm_codec.dart';
import 'package:vigyanbytes_transcribe/core/platform/sherpa_runtime_locator.dart';
import 'package:vigyanbytes_transcribe/core/platform/windows_dll_directory.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/meetsync_smoke.dart <model.onnx> <tokens.txt> <wav16k_mono.wav>',
    );
    exitCode = 64;
    return;
  }

  final modelPath = args[0];
  final tokensPath = args[1];
  final wavPath = args[2];

  if (Platform.isWindows) {
    final sherpaDllDir = SherpaRuntimeLocator.locateWindowsRuntimeDir();
    if (sherpaDllDir == null) {
      throw Exception('Vendored Sherpa runtime not found under assets/runtime/sherpa/windows');
    }
    setWindowsDllDirectory(sherpaDllDir);
    sherpa.initBindings(sherpaDllDir);
  } else {
    sherpa.initBindings();
  }
  final wavBytes = await _readWav16kMonoPcm16Bytes(wavPath);

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
      ),
      decodingMethod: 'greedy_search',
    ),
  );

  final stream = recognizer.createStream();
  stream.acceptWaveform(
    samples: PcmCodec.pcm16LeToFloat32(wavBytes),
    sampleRate: 16000,
  );
  recognizer.decode(stream);

  final result = recognizer.getResult(stream);
  stdout.writeln(result.text);

  stream.free();
  recognizer.free();
}

Future<Uint8List> _readWav16kMonoPcm16Bytes(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length < 44) {
    throw const FormatException('WAV file too short');
  }

  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  if (channels != 1 || sampleRate != 16000 || bitsPerSample != 16) {
    throw FormatException(
      'Expected 16kHz mono PCM16 WAV, got ${sampleRate}Hz ${channels}ch ${bitsPerSample}bit',
    );
  }

  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkId == 'data') {
      return bytes.sublist(offset, offset + chunkSize.toInt());
    }
    offset += chunkSize.toInt();
  }

  throw const FormatException('WAV data chunk not found');
}

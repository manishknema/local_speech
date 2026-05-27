import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigyanbytes_transcribe/background_engine/ai/lid_classifier.dart';
import 'package:vigyanbytes_transcribe/core/audio/pcm_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MMS-LID identifies canonical English and Hindi fixtures', () async {
    final model = File('assets/models/mms_lid.onnx');
    final enFixture = File('test_fixtures/wav16k/en_clean.wav');
    final hiFixture = File('test_fixtures/wav16k/hi_clean.wav');

    if (!await model.exists() || !await enFixture.exists() || !await hiFixture.exists()) {
      markTestSkipped('MMS-LID model or canonical WAV fixtures are not present.');
      return;
    }

    final lid = LidClassifier(modelPath: model.path);
    await lid.loadModel();
    addTearDown(lid.dispose);

    final enPredictions = await lid.inferTopKFromFloat32(
      _readCanonicalPcm16Wav(enFixture),
      k: 5,
    );
    final hiPredictions = await lid.inferTopKFromFloat32(
      _readCanonicalPcm16Wav(hiFixture),
      k: 5,
    );
    final en = enPredictions.first.language;
    final hi = hiPredictions.first.language;

    // Keep these prints while LID fixture baselines are being calibrated.
    // They make fixture/model mismatches visible in CI logs.
    // ignore: avoid_print
    print('MMS-LID fixture predictions: en_clean=$enPredictions hi_clean=$hiPredictions');

    expect(en, 'eng');
    expect(hi, 'hin');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Float32List _readCanonicalPcm16Wav(File file) {
  final wav = file.readAsBytesSync();
  final data = ByteData.sublistView(wav);

  expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

  int offset = 12;
  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  Uint8List? pcmBytes;

  while (offset + 8 <= wav.length) {
    final chunkId = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final payloadOffset = offset + 8;

    if (chunkId == 'fmt ') {
      final audioFormat = data.getUint16(payloadOffset, Endian.little);
      channels = data.getUint16(payloadOffset + 2, Endian.little);
      sampleRate = data.getUint32(payloadOffset + 4, Endian.little);
      bitsPerSample = data.getUint16(payloadOffset + 14, Endian.little);
      expect(audioFormat, 1);
    } else if (chunkId == 'data') {
      pcmBytes = Uint8List.sublistView(wav, payloadOffset, payloadOffset + chunkSize);
      break;
    }

    offset = payloadOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  expect(sampleRate, 16000);
  expect(channels, 1);
  expect(bitsPerSample, 16);
  expect(pcmBytes, isNotNull);

  return PcmCodec.pcm16LeToFloat32(pcmBytes!);
}

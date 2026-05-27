import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigyanbytes_transcribe/background_engine/ai/vad_utterance_segmenter.dart';
import 'package:vigyanbytes_transcribe/core/audio/pcm_codec.dart';

Uint8List _pcmFrame(int sampleCount, double amplitude) {
  return PcmCodec.float32ToPcm16Le(
    Float32List.fromList(List<double>.filled(sampleCount, amplitude)),
  );
}

void main() {
  test('does not flush short utterances below minimum segment duration', () {
    final segmenter = VadUtteranceSegmenter();
    final speechFrame = _pcmFrame(512, 0.5);
    final silenceFrame = _pcmFrame(512, 0.0);

    Float32List? result;
    for (int i = 0; i < 10; i++) {
      result = segmenter.processVadFrame(speechFrame, true);
    }
    for (int i = 0; i < 13; i++) {
      result = segmenter.processVadFrame(silenceFrame, false);
    }

    expect(result, isNull);
    expect(segmenter.state, VadUtteranceState.silence);
  });

  test('flushes completed utterance with preroll once silence tolerance is met', () {
    final segmenter = VadUtteranceSegmenter();
    final speechFrame = _pcmFrame(512, 0.5);
    final silenceFrame = _pcmFrame(512, 0.0);

    for (int i = 0; i < 10; i++) {
      segmenter.processVadFrame(silenceFrame, false);
    }

    Float32List? result;
    for (int i = 0; i < 32; i++) {
      result = segmenter.processVadFrame(speechFrame, true);
    }
    expect(result, isNull);

    for (int i = 0; i < 13; i++) {
      result = segmenter.processVadFrame(silenceFrame, false);
    }

    expect(result, isNotNull);
    expect(result!.length, greaterThanOrEqualTo(19200));
    expect(segmenter.state, VadUtteranceState.silence);
  });

  test('brief silence does not flush when speech resumes before tolerance', () {
    final segmenter = VadUtteranceSegmenter();
    final speechFrame = _pcmFrame(512, 0.5);
    final silenceFrame = _pcmFrame(512, 0.0);

    for (int i = 0; i < 24; i++) {
      segmenter.processVadFrame(speechFrame, true);
    }

    Float32List? result;
    for (int i = 0; i < 6; i++) {
      result = segmenter.processVadFrame(silenceFrame, false);
    }
    expect(result, isNull);
    expect(segmenter.state, VadUtteranceState.flushing);

    result = segmenter.processVadFrame(speechFrame, true);
    expect(result, isNull);
    expect(segmenter.state, VadUtteranceState.utteranceActive);
  });
}

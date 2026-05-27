import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigyanbytes_transcribe/background_engine/asr/asr_engine.dart';
import 'package:vigyanbytes_transcribe/background_engine/asr/dolphin_online_asr_engine.dart';
import 'package:vigyanbytes_transcribe/background_engine/asr/indic_transducer_asr_engine.dart';

void main() {
  final sampleAudio = Uint8List(32000);

  test('Dolphin profile reports online CTC topology', () async {
    final engine = DolphinOnlineAsrEngine();

    expect(engine.runtimeMode, AsrRuntimeMode.online);
    expect(engine.topology, AsrModelTopology.ctc);

    final transcript = await engine.transcribePcm16(sampleAudio);
    expect(transcript.engineId, 'dolphin_online');
    expect(transcript.runtimeMode, AsrRuntimeMode.online);
    expect(transcript.topology, AsrModelTopology.ctc);
    expect(transcript.language, 'auto');
  });

  test('Indic profile reports online transducer topology', () async {
    final engine = IndicTransducerAsrEngine();

    expect(engine.runtimeMode, AsrRuntimeMode.online);
    expect(engine.topology, AsrModelTopology.transducer);

    final transcript = await engine.transcribePcm16(sampleAudio);
    expect(transcript.engineId, 'indic_transducer');
    expect(transcript.runtimeMode, AsrRuntimeMode.online);
    expect(transcript.topology, AsrModelTopology.transducer);
    expect(transcript.language, 'indic');
  });
}

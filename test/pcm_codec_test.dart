import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigyanbytes_transcribe/core/audio/pcm_codec.dart';

void main() {
  test('pcm16LeToFloat32 preserves little-endian sample alignment', () {
    final bytes = Uint8List.fromList([
      0x00, 0x00, // 0
      0xff, 0x7f, // 32767
      0x00, 0x80, // -32768
      0x00, // ignored trailing byte
    ]);

    final samples = PcmCodec.pcm16LeToFloat32(bytes);

    expect(samples, hasLength(3));
    expect(samples[0], 0);
    expect(samples[1], closeTo(32767 / 32768.0, 1e-7));
    expect(samples[2], -1.0);
  });
}

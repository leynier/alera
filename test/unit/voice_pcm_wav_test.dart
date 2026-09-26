import 'dart:typed_data';

import 'package:alera/src/features/voice/infra/voice_audio_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pcm16ToWav writes the requested sample rate', () {
    final wav = pcm16ToWav(const <int>[0, 0], sampleRate: 24000);
    final header = ByteData.sublistView(wav);
    expect(header.getUint32(24, Endian.little), 24000);
    expect(header.getUint32(40, Endian.little), 2);
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

class MobileVoicePcmFrame({required this.samples, required this.rms}) {
  final Int16List samples;
  final double rms;
}

MobileVoicePcmFrame pcmFrameFromBytes(Uint8List chunk) {
  final sampleCount = chunk.length ~/ 2;
  final samples = Int16List(sampleCount);
  final view = ByteData.sublistView(chunk);
  var sumSquares = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final sample = view.getInt16(i * 2, Endian.little);
    samples[i] = sample;
    final normalized = sample / 32768.0;
    sumSquares += normalized * normalized;
  }
  return MobileVoicePcmFrame(
    samples: samples,
    rms: sampleCount == 0 ? 0 : math.sqrt(sumSquares / sampleCount),
  );
}

Uint8List pcm16ToWav(List<int> pcm, {int sampleRate = 16000}) {
  final data = Uint8List.fromList(pcm);
  final header = ByteData(44);
  final byteRate = sampleRate * 2;
  header.setUint32(0, 0x46464952, Endian.little);
  header.setUint32(4, 36 + data.length, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little);
  header.setUint32(12, 0x20746d66, Endian.little);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint32(36, 0x61746164, Endian.little);
  header.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...data]);
}

List<int> pcmBytes(Int16List samples) {
  return Uint8List.view(
    samples.buffer,
    samples.offsetInBytes,
    samples.lengthInBytes,
  );
}

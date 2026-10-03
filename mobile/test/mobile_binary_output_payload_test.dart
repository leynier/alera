import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/infra/mobile_binary_output_payload.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _message(String sessionId, List<int> data) {
  final id = utf8.encode(sessionId);
  return Uint8List.fromList(<int>[
    (id.length >> 8) & 0xff,
    id.length & 0xff,
    ...id,
    ...data,
  ]);
}

void main() {
  test('output is a view into the message, not a copy', () {
    final message = _message('sesión-1', <int>[0x1b, 0x5b, 0xff, 0x00]);

    final event = decodeMobileBinaryOutput(message)!;

    expect(event.sessionId, 'sesión-1');
    expect(event.data, <int>[0x1b, 0x5b, 0xff, 0x00]);
    // Shares the message's storage: a write through it shows in the event.
    message[message.length - 1] = 0x07;
    expect(event.data.last, 0x07);
  });

  test('a plain list still decodes', () {
    final event = decodeMobileBinaryOutput(
      List<int>.of(_message('s', <int>[1, 2])),
    )!;

    expect(event.sessionId, 's');
    expect(event.data, <int>[1, 2]);
  });

  test('malformed messages are dropped, not thrown', () {
    expect(decodeMobileBinaryOutput(<int>[0]), isNull);
    expect(decodeMobileBinaryOutput(<int>[0, 9, 1]), isNull);
    expect(decodeMobileBinaryOutput(_message('', <int>[1])), isNull);
  });
}

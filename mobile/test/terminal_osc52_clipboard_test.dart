import 'dart:convert';

import 'package:alera_mobile/src/features/terminal/domain/terminal_osc52_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a clipboard write with an explicit target', () {
    final payload = base64.encode(utf8.encode('copied ✓'));

    expect(decodeTerminalOsc52Payload('c', payload), 'copied ✓');
    expect(decodeTerminalOsc52Payload('s0', payload), 'copied ✓');
  });

  test('rejects queries, missing targets and malformed payloads', () {
    expect(decodeTerminalOsc52Payload('c', '?'), isNull);
    expect(decodeTerminalOsc52Payload('', 'Y29waWVk'), isNull);
    expect(decodeTerminalOsc52Payload('c', 'not base64!'), isNull);
    expect(decodeTerminalOsc52Payload('c', 'YWJj' * 40000), isNull);
  });
}

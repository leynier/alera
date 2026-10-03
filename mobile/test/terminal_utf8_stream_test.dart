import 'dart:convert';

import 'package:alera_mobile/src/features/terminal/domain/terminal_utf8_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a character split across output messages decodes whole', () {
    final stream = TerminalUtf8Stream();
    final bytes = utf8.encode('╭─ ñ ─╮');

    // Split inside the three-byte box-drawing character.
    expect(stream.decode(bytes.sublist(0, 2)), isEmpty);
    expect(stream.decode(bytes.sublist(2)), '╭─ ñ ─╮');
  });

  test('every split point of a mixed line round-trips', () {
    final text = 'a→b ✓ 😀 ñ ╰─╯';
    final bytes = utf8.encode(text);
    for (var cut = 0; cut <= bytes.length; cut += 1) {
      final stream = TerminalUtf8Stream();
      final decoded =
          stream.decode(bytes.sublist(0, cut)) +
          stream.decode(bytes.sublist(cut));
      expect(decoded, text, reason: 'split at byte $cut');
    }
  });

  test('reset drops a partial character with no continuation', () {
    final stream = TerminalUtf8Stream();
    final arrow = utf8.encode('→');

    expect(stream.decode(arrow.sublist(0, 1)), isEmpty);
    stream.reset();

    expect(stream.decode(utf8.encode('ok')), 'ok');
  });
}

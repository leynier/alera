import 'dart:convert';

import 'package:alera_browser/alera_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser titles drop controls and stop at a UTF-8 boundary', () {
    final raw = ' \u0000Docs\n${List.filled(300, '🚀').join()}\t ';

    final normalized = normalizeAleraBrowserTitle(raw);

    expect(utf8.encode(normalized), hasLength(aleraBrowserTitleMaximumBytes));
    expect(normalized, 'Docs${List.filled(255, '🚀').join()}');
    expect(
      normalized.runes.any(
        (rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f),
      ),
      isFalse,
    );
  });

  test(
    'browser title normalization drops trailing whitespace without growth',
    () {
      final normalized = normalizeAleraBrowserTitle(
        '  Account${List.filled(aleraBrowserTitleMaximumBytes * 2, ' ').join()}',
      );

      expect(normalized, 'Account');
    },
  );

  test('browser title does not expose boundary whitespace as trailing', () {
    final normalized = normalizeAleraBrowserTitle(
      '${List.filled(aleraBrowserTitleMaximumBytes - 1, 'a').join()} b',
    );

    expect(
      normalized,
      List.filled(aleraBrowserTitleMaximumBytes - 1, 'a').join(),
    );
  });
}

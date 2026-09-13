import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('SSH replay preserves cursor positioning before viewport reflow', () {
    final fixture = jsonDecode(
      File('test/fixtures/terminal_snapshot_geometry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final expected = Terminal()
      ..resize(fixture['cols'] as int, fixture['rows'] as int)
      ..write(fixture['snapshot'] as String)
      ..resize(fixture['viewportCols'] as int, fixture['viewportRows'] as int);
    final actual = Terminal()
      ..resize(fixture['viewportCols'] as int, fixture['viewportRows'] as int);
    // PTY reads may split any escape sequence across output chunks.
    for (final character in (fixture['replay'] as String).split('')) {
      actual.write(character);
    }
    expect(actual.buffer.getText(), expected.buffer.getText());
    expect(actual.buffer.cursorX, expected.buffer.cursorX);
    expect(actual.buffer.cursorY, expected.buffer.cursorY);
    expect(actual.viewWidth, fixture['viewportCols']);
    expect(actual.viewHeight, fixture['viewportRows']);
    final incorrect = Terminal()
      ..resize(fixture['viewportCols'] as int, fixture['viewportRows'] as int)
      ..write(fixture['snapshot'] as String);
    expect(incorrect.buffer.getText(), isNot(expected.buffer.getText()));
  });
}

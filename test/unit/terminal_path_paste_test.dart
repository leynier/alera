import 'package:alera/src/features/workbench/domain/terminal_path_paste.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPathForTerminalPaste', () {
    test('keeps bare paths unquoted and trailing-spaced', () {
      expect(formatPathForTerminalPaste('/tmp/foo'), '/tmp/foo ');
    });

    test('single-quotes paths that contain whitespace', () {
      expect(formatPathForTerminalPaste('/tmp/my file'), "'/tmp/my file' ");
    });

    test('quotes and escapes single quotes only when whitespace is present', () {
      // Jean-style: no whitespace means bare path, even with apostrophes.
      expect(formatPathForTerminalPaste("/tmp/it's"), "/tmp/it's ");
      expect(
        formatPathForTerminalPaste("/tmp/it's a file"),
        "'/tmp/it'\\''s a file' ",
      );
    });

    test('sanitizes ESC before quoting', () {
      expect(formatPathForTerminalPaste('/tmp/\x1bsecret'), '/tmp/␛secret ');
    });

    test('trims surrounding whitespace before formatting', () {
      expect(formatPathForTerminalPaste('  /tmp/foo  '), '/tmp/foo ');
    });

    test('returns empty for blank input', () {
      expect(formatPathForTerminalPaste('   '), '');
    });
  });

  group('formatPathsForTerminalPaste', () {
    test('joins multiple paths in order', () {
      expect(
        formatPathsForTerminalPaste(<String>['/a', '/b c', "/d'e", "/x y'z"]),
        "/a '/b c' /d'e '/x y'\\''z' ",
      );
    });

    test('skips blank entries', () {
      expect(formatPathsForTerminalPaste(<String>['', '  ', '/ok']), '/ok ');
    });

    test('returns empty for an empty iterable', () {
      expect(formatPathsForTerminalPaste(const <String>[]), '');
    });
  });
}

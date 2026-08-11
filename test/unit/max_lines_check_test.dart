import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_script_test_support.dart';

void main() {
  test(
    'max-lines baseline paths resolve from every desktop platform',
    () async {
      final result = await Process.run(dartScriptTestExecutable(), <String>[
        'tool/quality/check_max_lines.dart',
        '--roots',
        'rust/src/api,rust/alera-cli/src/terminal_host/server,'
            'rust/alera-cli/src/terminal_host,test/widget',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(result.stdout, contains('max-lines ratchet ok'));
    },
  );
}

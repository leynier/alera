import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;

part 'terminal_shell_startup_preparer_test_harness.dart';

part 'terminal_shell_startup_preparer_core_test_cases.dart';
part 'terminal_shell_startup_preparer_advanced_test_cases.dart';

late Directory tempDir;
late AleraTerminalShellStartupPreparer preparer;

void main() {
  group('AleraTerminalShellStartupPreparer', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'alera-terminal-startup-test-',
      );
      preparer = AleraTerminalShellStartupPreparer(
        applicationSupportDirectory: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    _registerTerminalShellStartupPreparerCoreTests();
    _registerTerminalShellStartupPreparerAdvancedTests();
  });
}

const List<String> _posixFallbackShells = <String>[
  '/bin/ash',
  '/bin/dash',
  '/bin/ksh',
  '/bin/mksh',
  '/bin/oksh',
  '/bin/sh',
];

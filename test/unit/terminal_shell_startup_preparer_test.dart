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

const String _expectedPosixRestoreManagedAgentEnvironment =
    'if [ -n "\${ALERA_CODEX_HOME:-}" ]; then export CODEX_HOME="\$ALERA_CODEX_HOME"; fi\n'
    'if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"; fi\n'
    'if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"; fi\n'
    'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n'
    'if [ -n "\${ALERA_COPILOT_HOME:-}" ]; then export COPILOT_HOME="\$ALERA_COPILOT_HOME"; fi\n'
    'if [ -n "\${ALERA_AGENT_WRAPPER_PATH:-}" ]; then __alera_new_path=""; __alera_appended=0; __alera_old_ifs="\${IFS-}"; IFS=":"; for __alera_entry in \${PATH:-}; do [ "\${__alera_entry}" = "\${ALERA_AGENT_WRAPPER_PATH}" ] && continue; if [ "\${__alera_appended}" -eq 0 ]; then __alera_new_path="\${__alera_entry}"; __alera_appended=1; else __alera_new_path="\${__alera_new_path}:\${__alera_entry}"; fi; done; IFS="\${__alera_old_ifs}"; if [ "\${__alera_appended}" -eq 1 ]; then export PATH="\${ALERA_AGENT_WRAPPER_PATH}:\${__alera_new_path}"; else export PATH="\${ALERA_AGENT_WRAPPER_PATH}"; fi; unset __alera_new_path __alera_appended __alera_old_ifs __alera_entry; fi\n';

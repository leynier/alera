import 'dart:io';

import 'package:alera/src/features/ai_assist/application/ai_assist_process_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a spawn failure keeps the install guidance and names the cause', () {
    expect(
      aiAssistProcessStartFailureMessage(
        subject: 'Codex',
        binary: 'codex',
        error: const ProcessException(
          'codex',
          <String>['exec'],
          'No such file or directory',
          2,
        ),
      ),
      'Codex could not be started: No such file or directory. Check that '
      'codex is installed and on PATH.',
    );
  });

  test('a non-process failure is cleaned of its type prefix', () {
    expect(
      aiAssistProcessStartFailureMessage(
        subject: 'Claude model discovery',
        binary: 'claude',
        error: StateError('permission denied.'),
      ),
      'Claude model discovery could not be started: Permission denied. '
      'Check that claude is installed and on PATH.',
    );
  });
}

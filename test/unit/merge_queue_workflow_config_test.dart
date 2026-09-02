import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'merge queue opts disposable Linux E2E into native clipboard access',
    () {
      final workflow = File('.github/workflows/merge-queue.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final desktopE2e = workflow.substring(
        workflow.indexOf('      - name: Desktop E2E'),
        workflow.indexOf('      - name: Report sccache statistics'),
      );

      expect(
        desktopE2e,
        contains("        env:\n          ALERA_NATIVE_TEST_CLIPBOARD: '1'"),
        reason:
            'terminal_input_native_test owns the clipboard and only runs when '
            'the disposable Xvfb job explicitly opts in',
      );
    },
  );
}

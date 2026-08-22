import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('development runtime uses an isolated debug bundle and flavor', () {
    final makefile = File('makefile').readAsStringSync();
    final debugContext = File(
      'tool/debug/alera_debug_context.dart',
    ).readAsStringSync();
    expect(
      makefile,
      contains('ALERA_RUNTIME_DEV_BUNDLE_DIR ?= .dart_tool/alera-dev'),
    );
    expect(makefile, contains('runtime-dev-build:'));
    expect(makefile, contains('app-debug-runtime-dev:'));
    expect(
      debugContext,
      contains('Future<int> buildRuntimeDev() => buildCli(release: false);'),
    );
    expect(
      debugContext,
      contains('The dev runtime can only be launched with the dev flavor.'),
    );
    expect(debugContext, contains('environment[\'ALERA_CLI_BUNDLE_DIR\'] ='));
  });
}

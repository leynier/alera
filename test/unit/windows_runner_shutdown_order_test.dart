import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner destroys the window after the loop and before CoUninitialize', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    final loop = source.indexOf('single_instance.RunMessageLoop(');
    final destroy = source.indexOf('window.Destroy();');
    final uninitialize = source.indexOf('::CoUninitialize();');

    expect(loop, isNonNegative);
    expect(destroy, greaterThan(loop));
    expect(uninitialize, greaterThan(destroy));
  });
}

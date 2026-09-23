import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray notice modify keeps the standard tooltip flag', () {
    final source = File('windows/runner/win32_desktop_presence.cpp')
        .readAsStringSync();
    final show = source.indexOf('bool Win32DesktopPresence::ShowTrayNotice');
    final flags = source.indexOf(
      'notice.uFlags = NIF_INFO | NIF_SHOWTIP;',
      show,
    );

    expect(show, isNonNegative);
    expect(flags, greaterThan(show));
  });
}

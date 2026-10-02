import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner tears down channels before the Flutter controller', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final destroy = source.indexOf('void FlutterWindow::OnDestroy()');
    final desktopDetach = source.indexOf(
      'desktop_presence_.Detach();',
      destroy,
    );
    final desktopChannel = source.indexOf(
      'desktop_presence_channel_.reset();',
      destroy,
    );
    final appMenuChannel = source.indexOf(
      'app_menu_channel_.reset();',
      destroy,
    );
    final controller = source.indexOf(
      'flutter_controller_ = nullptr;',
      destroy,
    );

    expect(destroy, isNonNegative);
    expect(desktopDetach, greaterThan(destroy));
    expect(desktopChannel, greaterThan(desktopDetach));
    expect(appMenuChannel, greaterThan(desktopChannel));
    expect(controller, greaterThan(appMenuChannel));
  });

  test('Windows font reload tolerates controller teardown', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final fontChange = source.indexOf('case WM_FONTCHANGE:');
    final guard = source.indexOf('if (flutter_controller_)', fontChange);

    expect(fontChange, isNonNegative);
    expect(guard, greaterThan(fontChange));
  });

  test('Windows failed startup balances COM after native teardown', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    final create = source.indexOf('if (!window.Create(');
    final destroy = source.indexOf('window.Destroy();', create);
    final uninitialize = source.indexOf('::CoUninitialize();', destroy);

    expect(create, isNonNegative);
    expect(destroy, greaterThan(create));
    expect(uninitialize, greaterThan(destroy));
  });

  test('Windows badge updates skip identical taskbar redraws', () {
    final source = File(
      'windows/runner/win32_desktop_presence.cpp',
    ).readAsStringSync();
    final setter = source.indexOf('void Win32DesktopPresence::SetBadgeCount');
    final guard = source.indexOf('if (badge_count_ == clamped)', setter);
    final redraw = source.indexOf('UpdateOverlay();', guard);

    expect(setter, isNonNegative);
    expect(guard, greaterThan(setter));
    expect(redraw, greaterThan(guard));
  });
}

import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('KeyboardPlatform.current follows the active target platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(KeyboardPlatform.current, KeyboardPlatform.macos);
    expect(KeyboardPlatform.current.isMacOS, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(KeyboardPlatform.current, KeyboardPlatform.windows);
    expect(KeyboardPlatform.current.isMacOS, isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(KeyboardPlatform.current, KeyboardPlatform.linux);
  });

  test('PlatformBindings.forPlatform returns the configured bindings', () {
    const bindings = PlatformBindings(
      macos: <String>['Meta+K'],
      windows: <String>['Ctrl+K'],
      linux: <String>['Ctrl+Shift+K'],
    );

    expect(bindings.forPlatform(KeyboardPlatform.macos), <String>['Meta+K']);
    expect(bindings.forPlatform(KeyboardPlatform.windows), <String>['Ctrl+K']);
    expect(
      bindings.forPlatform(KeyboardPlatform.linux),
      <String>['Ctrl+Shift+K'],
    );
  });

  test('KeyboardActionId.tabIndex only applies to go-to-tab actions', () {
    expect(KeyboardActionId.goToTab1.tabIndex, 1);
    expect(KeyboardActionId.goToTab5.tabIndex, 5);
    expect(KeyboardActionId.goToTab9.tabIndex, 9);
    expect(KeyboardActionId.closeTab.tabIndex, isNull);
  });
}

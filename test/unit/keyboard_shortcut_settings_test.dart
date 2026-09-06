import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyboardShortcutSettings', () {
    test('defaults are app-first with no overrides', () {
      const settings = KeyboardShortcutSettings.defaults;
      expect(settings.terminalPolicy, TerminalShortcutPolicy.appFirst);
      expect(settings.overrides, isEmpty);
    });

    test('round-trips overrides and policy through json', () {
      const settings = KeyboardShortcutSettings(
        terminalPolicy: .terminalFirst,
        overrides: <KeyboardActionId, List<String>>{
          KeyboardActionId.newTerminalTab: <String>['Mod+Shift+T'],
          KeyboardActionId.closeTab: <String>[],
        },
      );

      final restored = KeyboardShortcutSettings.fromJson(
        Map<String, Object?>.from(settings.toMap()),
      );

      expect(restored.terminalPolicy, TerminalShortcutPolicy.terminalFirst);
      expect(restored.overrides[KeyboardActionId.newTerminalTab], <String>[
        'Mod+Shift+T',
      ]);
      expect(restored.isDisabled(.closeTab), isTrue);
    });

    test('fromJson rejects invalid policy values', () {
      expect(
        () => KeyboardShortcutSettings.fromJson(<String, Object?>{
          'terminalPolicy': 'nonsense',
          'overrides': <String, Object?>{
            'newTerminalTab': <String>['Mod+T'],
          },
        }),
        throwsA(isA<MapperException>()),
      );
    });

    test('fromJson skips unknown action overrides', () {
      final restored = KeyboardShortcutSettings.fromJson(<String, Object?>{
        'terminalPolicy': 'appFirst',
        'overrides': <String, Object?>{
          'newTerminalTab': <String>['Mod+T'],
          'newBrowserTab': <String>['Mod+Shift+B'],
        },
      });
      expect(restored.overrides.keys, <KeyboardActionId>[
        KeyboardActionId.newTerminalTab,
      ]);
      expect(restored.overrides[KeyboardActionId.newTerminalTab], <String>[
        'Mod+T',
      ]);
    });

    test('copyWithOverride restores the default when given null', () {
      const settings = KeyboardShortcutSettings(
        overrides: <KeyboardActionId, List<String>>{
          KeyboardActionId.closeTab: <String>['Mod+Q'],
        },
      );
      final next = settings.copyWithOverride(.closeTab, null);
      expect(next.hasOverride(.closeTab), isFalse);
    });
  });
}

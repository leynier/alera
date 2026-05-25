import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraSettings', () {
    test('terminal defaults match current hardcoded terminal behavior', () {
      const terminal = TerminalSettings.defaults;

      expect(terminal.fontFamily, 'JetBrains Mono');
      expect(terminal.fontSize, 13);
      expect(terminal.fontWeight, 400);
      expect(terminal.lineHeight, 1.3);
      expect(terminal.padding, 12);
      expect(terminal.paddingX, 12);
      expect(terminal.paddingY, 12);
      expect(terminal.cursorShape, TerminalCursorShape.block);
      expect(terminal.cursorBlink, isFalse);
      expect(terminal.cursorOpacity, 1);
      expect(terminal.themeName, TerminalThemeNames.aleraDark);
      expect(terminal.backgroundOpacity, 1);
      expect(terminal.wordSeparators, isNull);
      expect(terminal.colorOverrides.isEmpty, isTrue);
      expect(terminal.scrollbackLines, 10000);
    });

    test('general destructive confirmations default on', () {
      const general = GeneralSettings.defaults;

      expect(general.confirmProjectRemoval, isTrue);
      expect(general.confirmWorkspaceRemoval, isTrue);
    });

    test('round-trips through json', () {
      const settings = AleraSettings(
        general: GeneralSettings(
          confirmProjectRemoval: false,
          confirmWorkspaceRemoval: false,
        ),
        terminal: TerminalSettings(
          fontFamily: 'SF Mono',
          fontSize: 15,
          fontWeight: 500,
          lineHeight: 1.4,
          paddingX: 8,
          paddingY: 10,
          cursorShape: TerminalCursorShape.bar,
          cursorBlink: true,
          cursorOpacity: 0.75,
          themeName: TerminalThemeNames.dracula,
          backgroundOpacity: 0.9,
          wordSeparators: ' /',
          colorOverrides: TerminalColorOverrides(
            foreground: '#eeeeee',
            background: '#111111',
            cursor: '#ff00ff',
            selection: '#333333',
          ),
          scrollbackLines: 50000,
        ),
        keyboard: KeyboardShortcutSettings(
          overrides: <KeyboardActionId, List<String>>{
            KeyboardActionId.closeTab: <String>['Mod+Shift+W'],
          },
        ),
      );

      final restored = AleraSettings.fromJson(
        Map<String, Object?>.from(settings.toMap()),
      );

      expect(restored.general.confirmProjectRemoval, isFalse);
      expect(restored.general.confirmWorkspaceRemoval, isFalse);
      expect(restored.terminal.fontFamily, 'SF Mono');
      expect(restored.terminal.fontSize, 15);
      expect(restored.terminal.fontWeight, 500);
      expect(restored.terminal.lineHeight, 1.4);
      expect(restored.terminal.paddingX, 8);
      expect(restored.terminal.paddingY, 10);
      expect(restored.terminal.cursorShape, TerminalCursorShape.bar);
      expect(restored.terminal.cursorBlink, isTrue);
      expect(restored.terminal.cursorOpacity, 0.75);
      expect(restored.terminal.themeName, TerminalThemeNames.dracula);
      expect(restored.terminal.backgroundOpacity, 0.9);
      expect(restored.terminal.wordSeparators, ' /');
      expect(restored.terminal.colorOverrides.foreground, '#eeeeee');
      expect(restored.terminal.colorOverrides.background, '#111111');
      expect(restored.terminal.colorOverrides.cursor, '#ff00ff');
      expect(restored.terminal.colorOverrides.selection, '#333333');
      expect(restored.terminal.scrollbackLines, 50000);
      expect(restored.keyboard.overrides[KeyboardActionId.closeTab], <String>[
        'Mod+Shift+W',
      ]);
    });

    test('fromJson requires the current top-level schema', () {
      expect(
        () => AleraSettings.fromJson(<String, Object?>{
          'general': <String, Object?>{
            'confirmProjectRemoval': false,
            'confirmWorkspaceRemoval': false,
          },
        }),
        throwsA(isA<MapperException>()),
      );
    });

    test('fromJson rejects invalid terminal field types', () {
      expect(
        () => AleraSettings.fromJson(<String, Object?>{
          'general': <String, Object?>{
            'confirmProjectRemoval': true,
            'confirmWorkspaceRemoval': true,
            'starClicked': false,
          },
          'terminal': <String, Object?>{
            'fontFamily': 'JetBrains Mono',
            'fontSize': 'large',
            'fontWeight': 400,
            'lineHeight': 1.3,
            'paddingX': 12,
            'paddingY': 12,
            'cursorShape': 'block',
            'cursorBlink': false,
            'cursorOpacity': 1,
            'themeName': TerminalThemeNames.aleraDark,
            'backgroundOpacity': 1,
            'colorOverrides': <String, Object?>{},
            'scrollbackLines': 10000,
          },
          'keyboard': <String, Object?>{
            'terminalPolicy': 'appFirst',
            'overrides': <String, Object?>{},
          },
        }),
        throwsA(isA<MapperException>()),
      );
    });

    test('terminal parsing preserves current-schema values', () {
      final restored = TerminalSettings.fromJson(<String, Object?>{
        'fontFamily': 'SF Mono',
        'fontSize': 18,
        'fontWeight': 600,
        'lineHeight': 1.5,
        'paddingX': 6,
        'paddingY': 10,
        'cursorShape': 'underline',
        'cursorBlink': true,
        'cursorOpacity': 0.6,
        'themeName': TerminalThemeNames.dracula,
        'backgroundOpacity': 0.85,
        'wordSeparators': ' /',
        'colorOverrides': <String, Object?>{'cursor': '#abcdef'},
        'scrollbackLines': 15000,
      });

      expect(restored.fontSize, 18);
      expect(restored.fontWeight, 600);
      expect(restored.paddingX, 6);
      expect(restored.paddingY, 10);
      expect(restored.cursorShape, TerminalCursorShape.underline);
      expect(restored.wordSeparators, ' /');
      expect(restored.colorOverrides.cursor, '#abcdef');
      expect(restored.scrollbackLines, 15000);
    });

    test('terminal parsing rejects missing required fields', () {
      expect(
        () => TerminalSettings.fromJson(<String, Object?>{
          'fontFamily': 'JetBrains Mono',
          'fontSize': 13,
        }),
        throwsA(isA<MapperException>()),
      );
    });
  });

  group('KeyboardShortcutSettings', () {
    test('defaults are app-first with no overrides', () {
      const settings = KeyboardShortcutSettings.defaults;
      expect(settings.terminalPolicy, TerminalShortcutPolicy.appFirst);
      expect(settings.overrides, isEmpty);
    });

    test('round-trips overrides and policy through json', () {
      const settings = KeyboardShortcutSettings(
        terminalPolicy: TerminalShortcutPolicy.terminalFirst,
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
      expect(restored.isDisabled(KeyboardActionId.closeTab), isTrue);
    });

    test('fromJson rejects unknown actions and invalid policy values', () {
      expect(
        () => KeyboardShortcutSettings.fromJson(<String, Object?>{
          'terminalPolicy': 'nonsense',
          'overrides': <String, Object?>{
            'newTerminalTab': <String>['Mod+T'],
            'thisActionDoesNotExist': <String>['Mod+Z'],
          },
        }),
        throwsA(isA<MapperException>()),
      );
    });

    test('copyWithOverride restores the default when given null', () {
      const settings = KeyboardShortcutSettings(
        overrides: <KeyboardActionId, List<String>>{
          KeyboardActionId.closeTab: <String>['Mod+Q'],
        },
      );
      final next = settings.copyWithOverride(KeyboardActionId.closeTab, null);
      expect(next.hasOverride(KeyboardActionId.closeTab), isFalse);
    });
  });
}

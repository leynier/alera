import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
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

    test('round-trips through json', () {
      const settings = AleraSettings(
        general: GeneralSettings.defaults,
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

      final restored = AleraSettings.fromJson(settings.toJson());

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
      expect(
        restored.keyboard.overrides[KeyboardActionId.closeTab],
        <String>['Mod+Shift+W'],
      );
    });

    test('fromJson falls back for invalid terminal fields', () {
      final restored = AleraSettings.fromJson(<String, Object?>{
        'terminal': <String, Object?>{
          'fontFamily': '',
          'fontSize': 'large',
          'fontWeight': 'heavy',
          'lineHeight': double.nan,
          'padding': null,
          'cursorShape': 'beam',
          'cursorOpacity': 'opaque',
          'themeName': '',
          'themePreset': 'unknown',
          'backgroundOpacity': <Object?>[],
          'wordSeparators': '',
          'colorOverrides': <String, Object?>{
            'foreground': 'bad',
            'background': '#111111',
          },
          'scrollbackLines': 'many',
        },
      });

      expect(restored.terminal, isNotNull);
      expect(
        restored.terminal.fontFamily,
        TerminalSettings.defaults.fontFamily,
      );
      expect(restored.terminal.fontSize, TerminalSettings.defaults.fontSize);
      expect(
        restored.terminal.fontWeight,
        TerminalSettings.defaults.fontWeight,
      );
      expect(
        restored.terminal.lineHeight,
        TerminalSettings.defaults.lineHeight,
      );
      expect(restored.terminal.padding, TerminalSettings.defaults.padding);
      expect(
        restored.terminal.cursorShape,
        TerminalSettings.defaults.cursorShape,
      );
      expect(
        restored.terminal.cursorOpacity,
        TerminalSettings.defaults.cursorOpacity,
      );
      expect(restored.terminal.themeName, TerminalSettings.defaults.themeName);
      expect(
        restored.terminal.backgroundOpacity,
        TerminalSettings.defaults.backgroundOpacity,
      );
      expect(restored.terminal.wordSeparators, isNull);
      expect(restored.terminal.colorOverrides.foreground, isNull);
      expect(restored.terminal.colorOverrides.background, '#111111');
      expect(
        restored.terminal.scrollbackLines,
        TerminalSettings.defaults.scrollbackLines,
      );
    });

    test('fromJson clamps numeric terminal values', () {
      final restored = TerminalSettings.fromJson(<String, Object?>{
        'fontSize': 100,
        'fontWeight': 950,
        'lineHeight': 0.1,
        'paddingX': 100,
        'paddingY': -4,
        'cursorOpacity': 2,
        'backgroundOpacity': -1,
        'scrollbackLines': 10,
      });

      expect(restored.fontSize, 32);
      expect(restored.fontWeight, 900);
      expect(restored.lineHeight, 0.8);
      expect(restored.paddingX, 64);
      expect(restored.paddingY, 0);
      expect(restored.cursorOpacity, 1);
      expect(restored.backgroundOpacity, 0);
      expect(restored.scrollbackLines, 100);
    });

    test('fromJson migrates legacy padding to both axes', () {
      final restored = TerminalSettings.fromJson(<String, Object?>{
        'padding': 9,
      });

      expect(restored.paddingX, 9);
      expect(restored.paddingY, 9);
    });

    test('fromJson migrates legacy terminal theme presets', () {
      final restored = TerminalSettings.fromJson(<String, Object?>{
        'themePreset': 'dracula',
      });

      expect(restored.themeName, TerminalThemeNames.dracula);
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

      final restored =
          KeyboardShortcutSettings.fromJson(settings.toJson());

      expect(restored.terminalPolicy, TerminalShortcutPolicy.terminalFirst);
      expect(
        restored.overrides[KeyboardActionId.newTerminalTab],
        <String>['Mod+Shift+T'],
      );
      expect(restored.isDisabled(KeyboardActionId.closeTab), isTrue);
    });

    test('fromJson drops unknown actions and unparsable chords', () {
      final restored = KeyboardShortcutSettings.fromJson(<String, Object?>{
        'terminalPolicy': 'nonsense',
        'overrides': <String, Object?>{
          'newTerminalTab': <Object?>['Mod+T', 'not a chord', 42],
          'thisActionDoesNotExist': <Object?>['Mod+Z'],
          'closeTab': 'not a list',
        },
      });

      expect(restored.terminalPolicy, TerminalShortcutPolicy.appFirst);
      expect(
        restored.overrides[KeyboardActionId.newTerminalTab],
        <String>['Mod+T'],
      );
      expect(restored.overrides.containsKey(KeyboardActionId.closeTab), isFalse);
      expect(restored.overrides.length, 1);
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

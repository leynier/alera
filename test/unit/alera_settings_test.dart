import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
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
      expect(terminal.hostEmptyShutdownDelaySeconds, 30);
      expect(terminal.hostDetachedSessionShutdownDelaySeconds, 60 * 60);
      expect(terminal.hostScrollbackBytes, 10 * 1000 * 1000);
    });

    test('general safety and hook defaults are conservative', () {
      const general = GeneralSettings.defaults;

      expect(general.confirmProjectRemoval, isTrue);
      expect(general.confirmWorkspaceRemoval, isTrue);
      expect(general.agentStatusHooks.codex, isFalse);
      expect(general.agentStatusHooks.claude, isFalse);
      expect(general.agentStatusHooks.copilot, isFalse);
      expect(general.agentStatusHooks.cursor, isFalse);
      expect(general.agentStatusHooks.agy, isFalse);
      expect(general.agentStatusHooks.opencode, isFalse);
      expect(general.agentStatusHooks.pi, isFalse);
      expect(general.agentStatusHooks.amp, isFalse);
      expect(general.agentStatusHooks.anyEnabled, isFalse);
      expect(general.agentStatusNotificationsEnabled, isFalse);
      expect(general.keepComputerAwakeWhileAgentsWork, isFalse);
    });

    test('editor defaults match current editor behavior', () {
      const editor = EditorSettings.defaults;

      expect(editor.tabSize, 4);
      expect(editor.themeName, EditorSyntaxThemeNames.alera);
    });

    test('small settings fragments round-trip through json', () {
      final overrides = TerminalColorOverrides.fromJson(<String, Object?>{
        'foreground': '#ffffff',
        'selection': '#123456',
      });
      final general = GeneralSettings.fromJson(<String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
        'starClicked': true,
        'confirmProjectRemoval': false,
        'confirmWorkspaceRemoval': true,
        'agentStatusHooks': <String, Object?>{
          'codex': true,
          'copilot': true,
          'cursor': true,
          'opencode': true,
          'amp': true,
        },
        'agentStatusNotificationsEnabled': true,
        'keepComputerAwakeWhileAgentsWork': true,
      });

      expect(overrides.foreground, '#ffffff');
      expect(overrides.selection, '#123456');
      expect(general.workspaceDirectory, '/tmp/workspaces');
      expect(general.starClicked, isTrue);
      expect(general.agentStatusHooks.codex, isTrue);
      expect(general.agentStatusHooks.claude, isFalse);
      expect(general.agentStatusHooks.copilot, isTrue);
      expect(general.agentStatusHooks.cursor, isTrue);
      expect(general.agentStatusHooks.agy, isFalse);
      expect(general.agentStatusHooks.opencode, isTrue);
      expect(general.agentStatusHooks.pi, isFalse);
      expect(general.agentStatusHooks.amp, isTrue);
      expect(general.agentStatusNotificationsEnabled, isTrue);
      expect(general.keepComputerAwakeWhileAgentsWork, isTrue);

      final hooks = AgentStatusHookSettings.fromJson(<String, Object?>{
        'claude': true,
        'pi': true,
      });
      expect(hooks.claude, isTrue);
      expect(hooks.pi, isTrue);
      expect(hooks.anyEnabled, isTrue);
    });

    test('round-trips through json', () {
      const settings = AleraSettings(
        general: GeneralSettings(
          confirmProjectRemoval: false,
          confirmWorkspaceRemoval: false,
          agentStatusHooks: AgentStatusHookSettings(
            codex: true,
            claude: true,
            cursor: true,
            agy: true,
            pi: true,
            amp: true,
          ),
          agentStatusNotificationsEnabled: true,
          keepComputerAwakeWhileAgentsWork: true,
        ),
        editor: EditorSettings(
          tabSize: 2,
          themeName: EditorSyntaxThemeNames.nord,
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
          hostEmptyShutdownDelaySeconds: 5,
          hostDetachedSessionShutdownDelaySeconds: 120,
          hostScrollbackBytes: 24 * 1000 * 1000,
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
      expect(restored.general.agentStatusHooks.codex, isTrue);
      expect(restored.general.agentStatusHooks.claude, isTrue);
      expect(restored.general.agentStatusHooks.copilot, isFalse);
      expect(restored.general.agentStatusHooks.cursor, isTrue);
      expect(restored.general.agentStatusHooks.agy, isTrue);
      expect(restored.general.agentStatusHooks.opencode, isFalse);
      expect(restored.general.agentStatusHooks.pi, isTrue);
      expect(restored.general.agentStatusHooks.amp, isTrue);
      expect(restored.general.agentStatusNotificationsEnabled, isTrue);
      expect(restored.general.keepComputerAwakeWhileAgentsWork, isTrue);
      expect(restored.editor.tabSize, 2);
      expect(restored.editor.themeName, EditorSyntaxThemeNames.nord);
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
      expect(restored.terminal.hostEmptyShutdownDelaySeconds, 5);
      expect(restored.terminal.hostDetachedSessionShutdownDelaySeconds, 120);
      expect(restored.terminal.hostScrollbackBytes, 24 * 1000 * 1000);
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
            'hostEmptyShutdownDelaySeconds': 30,
            'hostDetachedSessionShutdownDelaySeconds': 60 * 60,
            'hostScrollbackBytes': 10 * 1000 * 1000,
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
        'hostEmptyShutdownDelaySeconds': 45,
        'hostDetachedSessionShutdownDelaySeconds': 600,
        'hostScrollbackBytes': 16 * 1000 * 1000,
      });

      expect(restored.fontSize, 18);
      expect(restored.fontWeight, 600);
      expect(restored.paddingX, 6);
      expect(restored.paddingY, 10);
      expect(restored.cursorShape, TerminalCursorShape.underline);
      expect(restored.wordSeparators, ' /');
      expect(restored.colorOverrides.cursor, '#abcdef');
      expect(restored.scrollbackLines, 15000);
      expect(restored.hostEmptyShutdownDelaySeconds, 45);
      expect(restored.hostDetachedSessionShutdownDelaySeconds, 600);
      expect(restored.hostScrollbackBytes, 16 * 1000 * 1000);
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

    test('editor parsing preserves old settings without theme name', () {
      final restored = EditorSettings.fromJson(<String, Object?>{'tabSize': 2});

      expect(restored.tabSize, 2);
      expect(restored.themeName, EditorSyntaxThemeNames.alera);
    });

    test(
      'normalizes terminal hex colors only for valid current-schema values',
      () {
        expect(normalizeTerminalHexColor('#ABCDEF'), '#abcdef');
        expect(normalizeTerminalHexColor('123456'), '#123456');
        expect(normalizeTerminalHexColor(''), isNull);
        expect(normalizeTerminalHexColor(42), isNull);
      },
    );
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

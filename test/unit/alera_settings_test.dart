import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
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
      expect(terminal.tuiScrollSensitivity, 1);
      expect(terminal.clipboardOnSelect, isFalse);
      expect(terminal.allowOsc52Clipboard, isFalse);
      expect(terminal.showComposerByDefault, isFalse);
      expect(terminal.toolbarCorner, TerminalToolbarCorner.topRight);
      expect(terminal.hostEmptyShutdownDelaySeconds, 30);
      expect(terminal.hostDetachedSessionShutdownDelaySeconds, 60 * 60);
      expect(terminal.hostScrollbackBytes, 10 * 1000 * 1000);
      expect(terminal.keepRuntimeOpenOnAppQuit, isFalse);
    });

    test('general safety defaults are conservative', () {
      const general = GeneralSettings.defaults;

      expect(general.confirmProjectRemoval, isTrue);
      expect(general.confirmWorkspaceRemoval, isTrue);
      expect(general.keepAliveEnabled, isFalse);
      expect(general.showTrayIcon, isTrue);
      expect(general.showDockBadge, isTrue);
      expect(general.showTrayBadge, isTrue);
    });

    test('agent defaults are conservative', () {
      const agents = AgentSettings.defaults;

      expect(agents.agentStatusHooks.codex, isFalse);
      expect(agents.agentStatusHooks.claude, isFalse);
      expect(agents.agentStatusHooks.copilot, isFalse);
      expect(agents.agentStatusHooks.cursor, isFalse);
      expect(agents.agentStatusHooks.agy, isFalse);
      expect(agents.agentStatusHooks.opencode, isFalse);
      expect(agents.agentStatusHooks.opencode2, isFalse);
      expect(agents.agentStatusHooks.pi, isFalse);
      expect(agents.agentStatusHooks.amp, isFalse);
      expect(agents.agentStatusHooks.grok, isFalse);
      expect(agents.agentStatusHooks.fx, isFalse);
      expect(agents.agentStatusHooks.anyEnabled, isFalse);
      expect(agents.agentStatusNotificationsEnabled, isFalse);
      expect(agents.keepComputerAwakeWhileAgentsWork, isFalse);
      expect(agents.defaultAgentProfileId, isNull);
    });

    test('editor defaults match current editor behavior', () {
      const editor = EditorSettings.defaults;

      expect(editor.tabSize, 4);
      expect(editor.themeName, EditorSyntaxThemeNames.alera);
      expect(editor.autosaveEnabled, isFalse);
      expect(editor.autosaveDelaySeconds, 1);
      expect(editor.effectiveAutosaveDelaySeconds, 1);
      expect(editor.autosaveDebounce, const Duration(seconds: 1));
    });

    test('backward-compatible editor settings use autosave defaults', () {
      final editor = EditorSettings.fromJson(<String, Object?>{
        'tabSize': 2,
        'themeName': EditorSyntaxThemeNames.monokai,
      });

      expect(editor.tabSize, 2);
      expect(editor.themeName, EditorSyntaxThemeNames.monokai);
      expect(editor.autosaveEnabled, isFalse);
      expect(editor.autosaveDelaySeconds, 1);
    });

    test('bounds persisted autosave delay before scheduling', () {
      expect(
        EditorSettings(autosaveDelaySeconds: 0).effectiveAutosaveDelaySeconds,
        EditorSettings.minAutosaveDelaySeconds,
      );
      expect(
        EditorSettings(autosaveDelaySeconds: 999).effectiveAutosaveDelaySeconds,
        EditorSettings.maxAutosaveDelaySeconds,
      );
    });

    test('AI Assist defaults cover Alera agents conservatively', () {
      const ai = AiAssistSettings.defaults;

      expect(ai.enabled, isTrue);
      expect(ai.agent, AiAssistAgent.codex);
      expect(ai.timeoutSeconds, 120);
      expect(ai.customCommand, isEmpty);
      expect(ai.modelFor(.codex), isNull);
      expect(
        AiAssistAgent.values
            .where((agent) => agent != AiAssistAgent.custom)
            .map((agent) => agent.agentType)
            .whereType<Object>()
            .length,
        11,
      );
    });

    test('small settings fragments round-trip through json', () {
      final diagnostics = DiagnosticsSettings.fromJson(<String, Object?>{
        'logLevel': 'debug',
        'crashReportingEnabled': true,
      });
      expect(diagnostics.logLevel, DiagnosticsLogLevel.debug);
      expect(diagnostics.crashReportingEnabled, isTrue);

      final overrides = TerminalColorOverrides.fromJson(<String, Object?>{
        'foreground': '#ffffff',
        'selection': '#123456',
      });
      final general = GeneralSettings.fromJson(<String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
        'starClicked': true,
        'confirmProjectRemoval': false,
        'confirmWorkspaceRemoval': true,
      });
      final agents = AgentSettings.fromJson(<String, Object?>{
        'agentStatusHooks': <String, Object?>{
          'codex': true,
          'copilot': true,
          'cursor': true,
          'opencode': true,
          'amp': true,
        },
        'agentStatusNotificationsEnabled': true,
        'keepComputerAwakeWhileAgentsWork': true,
        'defaultAgentProfileId': 'prof_1',
      });

      expect(overrides.foreground, '#ffffff');
      expect(overrides.selection, '#123456');
      expect(general.workspaceDirectory, '/tmp/workspaces');
      expect(general.starClicked, isTrue);
      expect(general.showTrayIcon, isTrue);
      expect(general.showDockBadge, isTrue);
      expect(agents.agentStatusHooks.codex, isTrue);
      expect(agents.agentStatusHooks.claude, isFalse);
      expect(agents.agentStatusHooks.copilot, isTrue);
      expect(agents.agentStatusHooks.cursor, isTrue);
      expect(agents.agentStatusHooks.agy, isFalse);
      expect(agents.agentStatusHooks.opencode, isTrue);
      expect(agents.agentStatusHooks.pi, isFalse);
      expect(agents.agentStatusHooks.amp, isTrue);
      expect(agents.agentStatusNotificationsEnabled, isTrue);
      expect(agents.keepComputerAwakeWhileAgentsWork, isTrue);
      expect(agents.defaultAgentProfileId, 'prof_1');

      final hooks = AgentStatusHookSettings.fromJson(<String, Object?>{
        'claude': true,
        'pi': true,
      });
      expect(hooks.claude, isTrue);
      expect(hooks.pi, isTrue);
      expect(hooks.grok, isFalse);
      expect(hooks.fx, isFalse);
      expect(hooks.anyEnabled, isTrue);
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
        'tuiScrollSensitivity': 4,
        'clipboardOnSelect': true,
        'allowOsc52Clipboard': true,
        'showComposerByDefault': true,
        'toolbarCorner': 'bottomLeft',
        'hostEmptyShutdownDelaySeconds': 45,
        'hostDetachedSessionShutdownDelaySeconds': 600,
        'hostScrollbackBytes': 16 * 1000 * 1000,
        'keepRuntimeOpenOnAppQuit': false,
      });

      expect(restored.fontSize, 18);
      expect(restored.fontWeight, 600);
      expect(restored.paddingX, 6);
      expect(restored.paddingY, 10);
      expect(restored.cursorShape, TerminalCursorShape.underline);
      expect(restored.wordSeparators, ' /');
      expect(restored.colorOverrides.cursor, '#abcdef');
      expect(restored.scrollbackLines, 15000);
      expect(restored.tuiScrollSensitivity, 4);
      expect(restored.clipboardOnSelect, isTrue);
      expect(restored.allowOsc52Clipboard, isTrue);
      expect(restored.showComposerByDefault, isTrue);
      expect(restored.toolbarCorner, TerminalToolbarCorner.bottomLeft);
      expect(restored.hostEmptyShutdownDelaySeconds, 45);
      expect(restored.hostDetachedSessionShutdownDelaySeconds, 600);
      expect(restored.hostScrollbackBytes, 16 * 1000 * 1000);
      expect(restored.keepRuntimeOpenOnAppQuit, isFalse);
    });

    test(
      'legacy stopRuntimeOnAppQuit migrates to keepRuntimeOpenOnAppQuit',
      () {
        final keptOpen = TerminalSettings.fromJson(<String, Object?>{
          'fontFamily': 'JetBrains Mono',
          'fontSize': 13,
          'lineHeight': 1.3,
          'cursorShape': 'block',
          'scrollbackLines': 10000,
          'stopRuntimeOnAppQuit': false,
        });
        final stoppedOnQuit = TerminalSettings.fromJson(<String, Object?>{
          'fontFamily': 'JetBrains Mono',
          'fontSize': 13,
          'lineHeight': 1.3,
          'cursorShape': 'block',
          'scrollbackLines': 10000,
          'stopRuntimeOnAppQuit': true,
        });
        final omittedQuitFlag = TerminalSettings.fromJson(<String, Object?>{
          'fontFamily': 'JetBrains Mono',
          'fontSize': 13,
          'lineHeight': 1.3,
          'cursorShape': 'block',
          'scrollbackLines': 10000,
        });

        expect(keptOpen.keepRuntimeOpenOnAppQuit, isTrue);
        expect(stoppedOnQuit.keepRuntimeOpenOnAppQuit, isFalse);
        expect(omittedQuitFlag.keepRuntimeOpenOnAppQuit, isTrue);
        expect(omittedQuitFlag.toolbarCorner, TerminalToolbarCorner.topRight);
      },
    );

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

    test('legacy blob lifts agent keys from general into agents', () {
      final restored = AleraSettings.fromJson(<String, Object?>{
        'general': <String, Object?>{
          'workspaceDirectory': '/tmp/workspaces',
          'starClicked': true,
          'confirmProjectRemoval': false,
          'confirmWorkspaceRemoval': true,
          'agentStatusHooks': <String, Object?>{'codex': true, 'pi': true},
          'agentStatusNotificationsEnabled': true,
          'keepComputerAwakeWhileAgentsWork': true,
        },
        'terminal': Map<String, Object?>.from(
          TerminalSettings.defaults.toMap(),
        ),
        'keyboard': <String, Object?>{
          'terminalPolicy': 'appFirst',
          'overrides': <String, Object?>{},
        },
      });

      expect(restored.general.workspaceDirectory, '/tmp/workspaces');
      expect(restored.general.confirmProjectRemoval, isFalse);
      expect(restored.agents.agentStatusHooks.codex, isTrue);
      expect(restored.agents.agentStatusHooks.pi, isTrue);
      expect(restored.agents.agentStatusHooks.claude, isFalse);
      expect(restored.agents.agentStatusNotificationsEnabled, isTrue);
      expect(restored.agents.keepComputerAwakeWhileAgentsWork, isTrue);
    });

    test('legacy blob without agent keys decodes with agent defaults', () {
      final restored = AleraSettings.fromJson(<String, Object?>{
        'general': <String, Object?>{
          'confirmProjectRemoval': true,
          'confirmWorkspaceRemoval': true,
          'starClicked': false,
        },
        'terminal': Map<String, Object?>.from(
          TerminalSettings.defaults.toMap(),
        ),
        'keyboard': <String, Object?>{
          'terminalPolicy': 'appFirst',
          'overrides': <String, Object?>{},
        },
      });

      expect(restored.agents, AgentSettings.defaults);
    });

    test('mixed blob prefers the agents sub-map over legacy general keys', () {
      final restored = AleraSettings.fromJson(<String, Object?>{
        'general': <String, Object?>{
          'confirmProjectRemoval': true,
          'confirmWorkspaceRemoval': true,
          'starClicked': false,
          'agentStatusHooks': <String, Object?>{'codex': true},
          'agentStatusNotificationsEnabled': true,
        },
        'agents': <String, Object?>{
          'agentStatusHooks': <String, Object?>{'claude': true},
          'agentStatusNotificationsEnabled': false,
        },
        'terminal': Map<String, Object?>.from(
          TerminalSettings.defaults.toMap(),
        ),
        'keyboard': <String, Object?>{
          'terminalPolicy': 'appFirst',
          'overrides': <String, Object?>{},
        },
      });

      expect(restored.agents.agentStatusHooks.codex, isFalse);
      expect(restored.agents.agentStatusHooks.claude, isTrue);
      expect(restored.agents.agentStatusNotificationsEnabled, isFalse);
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
}

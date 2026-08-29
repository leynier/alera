import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraSettings JSON', () {
    test('round-trips through json', () {
      const settings = AleraSettings(
        general: GeneralSettings(
          confirmProjectRemoval: false,
          confirmWorkspaceRemoval: false,
          keepAliveEnabled: true,
          showTrayIcon: false,
          showDockBadge: false,
          showTrayBadge: false,
        ),
        agents: AgentSettings(
          agentStatusHooks: AgentStatusHookSettings(
            codex: true,
            claude: true,
            cursor: true,
            agy: true,
            pi: true,
            amp: true,
            grok: true,
            fx: true,
          ),
          agentStatusNotificationsEnabled: true,
          keepComputerAwakeWhileAgentsWork: true,
          defaultAgentProfileId: 'prof_1',
        ),
        editor: EditorSettings(
          tabSize: 2,
          themeName: EditorSyntaxThemeNames.nord,
          autosaveEnabled: true,
          autosaveDelaySeconds: 3,
        ),
        aiAssist: AiAssistSettings(
          agent: AiAssistAgent.agy,
          selectedModelByAgent: <AiAssistAgent, String>{
            AiAssistAgent.agy: 'Gemini 3.5 Flash (Medium)',
          },
          instructionsByOperation: <AiAssistOperation, String>{
            AiAssistOperation.commitMessage: 'Use conventional commits.',
          },
        ),
        codexChat: CodexChatSettings(
          selectedModel: 'gpt-current',
          reasoningEffort: 'xhigh',
          speedMode: 'fast',
          permissionMode: 'never',
          planMode: true,
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
          toolbarCorner: TerminalToolbarCorner.bottomRight,
        ),
        keyboard: KeyboardShortcutSettings(
          overrides: <KeyboardActionId, List<String>>{
            KeyboardActionId.closeTab: <String>['Mod+Shift+W'],
          },
        ),
      );

      final encoded = settings.toMap();
      expect(encoded.containsKey('aiTextGeneration'), isTrue);
      expect(encoded.containsKey('aiAssist'), isFalse);

      final restored = AleraSettings.fromJson(
        Map<String, Object?>.from(encoded),
      );

      expect(restored.general.confirmProjectRemoval, isFalse);
      expect(restored.general.confirmWorkspaceRemoval, isFalse);
      expect(restored.general.keepAliveEnabled, isTrue);
      expect(restored.general.showTrayIcon, isFalse);
      expect(restored.general.showDockBadge, isFalse);
      expect(restored.general.showTrayBadge, isFalse);
      expect(restored.agents.agentStatusHooks.codex, isTrue);
      expect(restored.agents.agentStatusHooks.claude, isTrue);
      expect(restored.agents.agentStatusHooks.copilot, isFalse);
      expect(restored.agents.agentStatusHooks.cursor, isTrue);
      expect(restored.agents.agentStatusHooks.agy, isTrue);
      expect(restored.agents.agentStatusHooks.opencode, isFalse);
      expect(restored.agents.agentStatusHooks.pi, isTrue);
      expect(restored.agents.agentStatusHooks.amp, isTrue);
      expect(restored.agents.agentStatusHooks.grok, isTrue);
      expect(restored.agents.agentStatusHooks.fx, isTrue);
      expect(restored.agents.agentStatusNotificationsEnabled, isTrue);
      expect(restored.agents.keepComputerAwakeWhileAgentsWork, isTrue);
      expect(restored.agents.defaultAgentProfileId, 'prof_1');
      expect(restored.editor.tabSize, 2);
      expect(restored.editor.themeName, EditorSyntaxThemeNames.nord);
      expect(restored.editor.autosaveEnabled, isTrue);
      expect(restored.editor.autosaveDelaySeconds, 3);
      expect(restored.aiAssist.agent, AiAssistAgent.agy);
      expect(
        restored.aiAssist.modelFor(AiAssistAgent.agy),
        'Gemini 3.5 Flash (Medium)',
      );
      expect(
        restored.aiAssist.instructionsFor(AiAssistOperation.commitMessage),
        'Use conventional commits.',
      );
      expect(restored.codexChat.selectedModel, 'gpt-current');
      expect(restored.codexChat.reasoningEffort, 'xhigh');
      expect(restored.codexChat.speedMode, 'fast');
      expect(restored.codexChat.permissionMode, 'never');
      expect(restored.codexChat.planMode, isTrue);
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
      expect(
        restored.terminal.toolbarCorner,
        TerminalToolbarCorner.bottomRight,
      );
      expect(restored.keyboard.overrides[KeyboardActionId.closeTab], <String>[
        'Mod+Shift+W',
      ]);
    });
  });
}

import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTabRecord _tab(Map<String, Object?> payload) => WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: 'ws-1',
  title: 'Chat',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceTabKind.agentChat,
  payload: payload,
);

void main() {
  test(
    'chat bindings reject blank and non-string values and prefer current ids',
    () {
      final current = _tab(<String, Object?>{
        'chatId': 'current',
        'agentChatId': 'legacy',
        'provider': '  ',
        'model': 42,
      });
      expect(current.agentChatId, 'current');
      expect(current.agentChatProvider, isNull);
      expect(current.agentChatModel, isNull);
      expect(
        _tab(<String, Object?>{'chatId': ' ', 'agentChatId': 'legacy'})
            .agentChatId,
        'legacy',
      );
    },
  );

  test(
    'known providers have readable labels and their bundled agent marks',
    () {
      final providers = <String, (String, AgentType?)>{
        'codex': ('Codex', AgentType.codex),
        'claudeAgent': ('Claude', AgentType.claude),
        'cursor': ('Cursor', AgentType.cursor),
        'grok': ('Grok', AgentType.grok),
        'opencode': ('OpenCode', AgentType.opencode),
        'antigravity': ('Antigravity', AgentType.agy),
        'pi': ('Pi', AgentType.pi),
        'muse': ('Muse', null),
        'acpRegistry': ('ACP Agent', null),
        '': ('Agent', null),
        'custom': ('custom', null),
      };
      for (final MapEntry(key: provider, value: (label, mark))
          in providers.entries) {
        expect(agentChatProviderFallbackLabel(provider), label);
        expect(agentChatAgentType(provider), mark);
      }
    },
  );
}

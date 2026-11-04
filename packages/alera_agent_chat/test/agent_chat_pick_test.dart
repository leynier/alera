import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

const _target = AgentChatProviderInstance(
  id: 'claude-work',
  provider: 'claudeAgent',
  label: 'Claude Work',
);

void main() {
  test('empty drafts switch silently while existing conversations confirm the handoff', () {
    expect(
      agentChatPickDecision(
        neverSent: true,
        switchesProvider: true,
        canSwitchProvider: true,
      ),
      AgentChatPickDecision.apply,
    );
    expect(
      agentChatPickDecision(
        neverSent: false,
        switchesProvider: true,
        canSwitchProvider: true,
      ),
      AgentChatPickDecision.confirmHandoff,
    );
  });

  test(
    'busy sessions block provider changes but keep model-only picks available',
    () {
      expect(
        agentChatPickDecision(
          neverSent: true,
          switchesProvider: true,
          canSwitchProvider: false,
        ),
        AgentChatPickDecision.blocked,
      );
      expect(
        agentChatPickDecision(
          neverSent: false,
          switchesProvider: true,
          canSwitchProvider: false,
        ),
        AgentChatPickDecision.blocked,
      );
      expect(
        agentChatPickDecision(
          neverSent: false,
          switchesProvider: false,
          canSwitchProvider: false,
        ),
        AgentChatPickDecision.apply,
      );
    },
  );

  test('a combined pick changes instance and resets default model in one configure', () {
    final config = agentChatConfigurationForPick(
      target: _target,
      modelId: null,
      currentInstanceId: 'codex',
    );
    expect(config.toJson(), <String, Object?>{
      'providerInstanceId': 'claude-work',
      'model': null,
    });
    expect(config.switchesProvider, isTrue);
    expect(config.isEmpty, isFalse);
    final modelOnly = agentChatConfigurationForPick(
      target: _target,
      modelId: 'sonnet',
      currentInstanceId: 'claude-work',
    );
    expect(modelOnly.toJson(), <String, Object?>{'model': 'sonnet'});
    expect(modelOnly.switchesProvider, isFalse);
  });

  test('never-sent reuse needs a loaded snapshot with no older history', () {
    const empty = AgentChatSnapshot(chatId: 'c', workspaceId: 'w', cursor: 0);
    expect(AgentChatThread.fromSnapshot(empty).neverSent, isTrue);
    expect(
      AgentChatThread.fromSnapshot(empty.copyWith(historyBefore: 'older'))
          .neverSent,
      isFalse,
    );
  });

  test('blocked picker rows use the shared composer busy reason', () {
    final rows = agentChatPickerGroups(
      providers: const <AgentChatProviderInstance>[_target],
      currentSelection: const AgentChatSelection(providerInstanceId: 'codex'),
      canSwitchProvider: false,
    ).single.rows;
    expect(rows.single.disabledReason, agentChatSwitchBusyReason);
  });
}

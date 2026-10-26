import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_shortcut_target.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatComposerSettings _settings({
  String? effort,
  AgentChatInteractionMode mode = AgentChatInteractionMode.standard,
  bool plan = true,
}) => AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: AgentChatSession(
    model: 'gpt',
    reasoningEffort: effort,
    interactionMode: mode,
  ),
  providers: <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'Codex',
      interactionModes: <AgentChatInteractionMode>[
        AgentChatInteractionMode.standard,
        if (plan) AgentChatInteractionMode.plan,
      ],
      models: const <AgentChatModelOption>[
        AgentChatModelOption(
          id: 'gpt',
          label: 'GPT',
          reasoningEfforts: <String>['low', 'medium', 'high'],
          defaultReasoningEffort: 'medium',
        ),
      ],
    ),
  ],
  canSwitchProvider: true,
  configuring: false,
);

void main() {
  test('effort steps one level and stops at either end', () {
    expect(
      agentChatSteppedEffort(_settings(effort: 'medium'), 1)?.reasoningEffort,
      'high',
    );
    expect(agentChatSteppedEffort(_settings(effort: 'high'), 1), isNull);
    expect(agentChatSteppedEffort(_settings(effort: 'low'), -1), isNull);
    // Stepping onto the model default resets the override.
    expect(
      agentChatSteppedEffort(
        _settings(effort: 'high'),
        -1,
      )?.resetReasoningEffort,
      isTrue,
    );
    // Without an override the default is the current level.
    expect(agentChatSteppedEffort(_settings(), -1)?.reasoningEffort, 'low');
  });

  test('mode toggles plan only where the agent plans', () {
    expect(
      agentChatNextMode(_settings())?.interactionMode,
      AgentChatInteractionMode.plan,
    );
    expect(
      agentChatNextMode(_settings(mode: AgentChatInteractionMode.plan))
          ?.interactionMode,
      AgentChatInteractionMode.standard,
    );
    expect(agentChatNextMode(_settings(plan: false)), isNull);
  });
}

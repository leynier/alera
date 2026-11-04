import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

List<AgentChatSlashCommand> _commands(
  AgentChatSlashCommandState state, {
  String query = '',
}) => <AgentChatSlashCommand>[
  for (final option in agentChatSlashCommandOptions(state, query: query))
    option.command,
];

void main() {
  test('plan and default mode only show when the agent has a plan mode', () {
    expect(_commands(const AgentChatSlashCommandState()), <Object>[
      AgentChatSlashCommand.model,
      AgentChatSlashCommand.usage,
    ]);
    expect(
      _commands(const AgentChatSlashCommandState(planModeSupported: true)),
      <Object>[
        AgentChatSlashCommand.model,
        AgentChatSlashCommand.plan,
        AgentChatSlashCommand.standard,
        AgentChatSlashCommand.usage,
      ],
    );
  });

  test('the current interaction mode disables its own command', () {
    final standard = agentChatSlashCommandOptions(
      const AgentChatSlashCommandState(planModeSupported: true),
    );
    expect(
      standard
          .firstWhere((option) => option.command.name == 'plan')
          .disabledReason,
      isNull,
    );
    expect(
      standard
          .firstWhere((option) => option.command.name == 'default')
          .disabledReason,
      agentChatSlashCommandDefaultActiveReason,
    );

    final plan = agentChatSlashCommandOptions(
      const AgentChatSlashCommandState(
        planModeSupported: true,
        interactionMode: AgentChatInteractionMode.plan,
      ),
    );
    expect(
      plan.firstWhere((option) => option.command.name == 'plan').enabled,
      isFalse,
    );
    expect(
      plan.firstWhere((option) => option.command.name == 'default').enabled,
      isTrue,
    );
  });

  test('commands that cannot run say why', () {
    final options = agentChatSlashCommandOptions(
      const AgentChatSlashCommandState(
        modelPickerAvailable: false,
        modelPickerBlockedReason: 'Agents are loading.',
        planModeSupported: true,
        interactionMode: AgentChatInteractionMode.plan,
        configuring: true,
      ),
    );
    expect(
      <String?>[for (final option in options) option.disabledReason],
      <String?>[
        'Agents are loading.',
        agentChatSlashCommandConfiguringReason,
        agentChatSlashCommandConfiguringReason,
        agentChatSlashCommandUsageUnavailableReason,
      ],
    );
  });

  test('the query filters by name, prefixes first, ignoring case', () {
    const state = AgentChatSlashCommandState(planModeSupported: true);
    expect(_commands(state, query: 'MO'), <Object>[
      AgentChatSlashCommand.model,
    ]);
    // None of them starts with "a", so they keep the table order.
    expect(_commands(state, query: 'a'), <Object>[
      AgentChatSlashCommand.plan,
      AgentChatSlashCommand.standard,
      AgentChatSlashCommand.usage,
    ]);
    expect(_commands(state, query: 'u'), <Object>[
      AgentChatSlashCommand.usage,
      AgentChatSlashCommand.standard,
    ]);
    expect(_commands(state, query: 'zzz'), isEmpty);
  });

  test('mode commands name the mode they switch to', () {
    expect(
      agentChatSlashCommandInteractionMode(AgentChatSlashCommand.plan),
      AgentChatInteractionMode.plan,
    );
    expect(
      agentChatSlashCommandInteractionMode(AgentChatSlashCommand.standard),
      AgentChatInteractionMode.standard,
    );
    expect(
      agentChatSlashCommandInteractionMode(AgentChatSlashCommand.model),
      isNull,
    );
    expect(AgentChatSlashCommand.standard.label, '/default');
  });
}

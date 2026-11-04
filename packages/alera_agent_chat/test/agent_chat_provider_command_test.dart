import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

List<String> _names(
  AgentChatSlashCommandState state, {
  String query = '',
}) => <String>[
  for (final entry in agentChatSlashMenuEntries(state, query: query))
    switch (entry) {
      AgentChatSlashMenuLocalCommand(:final option) => 'local:${option.name}',
      AgentChatSlashMenuProviderCommand(:final command) =>
        'agent:${command.name}',
      AgentChatSlashMenuSkill(:final skill) => 'skill:${skill.name}',
    },
];

extension on AgentChatSlashCommandOption {
  String get name => command.name;
}

void main() {
  test('the session reads the commands the runtime projected', () {
    final session = AgentChatSession.fromJson(<String, Object?>{
      'status': 'ready',
      'commands': <Object?>[
        <String, Object?>{
          'name': 'compact',
          'description': ' Summarize the conversation ',
          'input': <String, Object?>{'hint': 'focus'},
        },
        <String, Object?>{'name': '/review'},
        <String, Object?>{'name': 'COMPACT'},
        <String, Object?>{'name': 'two words'},
        <String, Object?>{'description': 'no name'},
        'not a command',
      ],
    });
    expect(session.commands, const <AgentChatProviderCommand>[
      AgentChatProviderCommand(
        name: 'compact',
        description: 'Summarize the conversation',
        inputHint: 'focus',
      ),
      AgentChatProviderCommand(name: 'review'),
    ]);
    expect(session.commands.first.label, '/compact');
    expect(session.commands.first.insertion, '/compact ');
    expect(AgentChatSession.fromJson(<String, Object?>{}).commands, isEmpty);
  });

  test('agent commands follow the local ones, which win a name clash', () {
    const state = AgentChatSlashCommandState(
      providerCommands: <AgentChatProviderCommand>[
        AgentChatProviderCommand(name: 'compact'),
        AgentChatProviderCommand(name: 'Model'),
        // Hidden here because the agent has no plan mode, yet still local.
        AgentChatProviderCommand(name: 'plan'),
        AgentChatProviderCommand(name: 'init'),
        AgentChatProviderCommand(name: 'INIT'),
      ],
    );
    expect(_names(state), <String>[
      'local:model',
      'local:usage',
      'agent:compact',
      'agent:init',
    ]);
  });

  // T3 Code's ranking: a shorter prefix match beats a longer one, then
  // substrings, then descriptions (`usage` mentions limits).
  test('the query ranks matches like T3 Code across both kinds', () {
    const state = AgentChatSlashCommandState(
      providerCommands: <AgentChatProviderCommand>[
        AgentChatProviderCommand(name: 'Mcp'),
        AgentChatProviderCommand(name: 'summary'),
      ],
    );
    expect(_names(state, query: 'M'), <String>[
      'agent:Mcp',
      'local:model',
      'agent:summary',
      'local:usage',
    ]);
    expect(_names(state, query: 'sum'), <String>['agent:summary']);
    expect(_names(state, query: 'zzz'), isEmpty);
  });
}

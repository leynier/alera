import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 10, 12, 10);

AgentChatUsageReading _reading(
  String provider,
  double used, {
  Duration? resetsIn = const Duration(hours: 1),
  bool fresh = true,
}) => AgentChatUsageReading(
  provider: provider,
  fresh: fresh,
  meters: <AgentChatUsageMeter>[
    AgentChatUsageMeter(
      usedPercent: used,
      resetsAt: resetsIn == null ? null : _now.add(resetsIn),
    ),
  ],
);

const List<AgentChatProviderInstance> _providers = <AgentChatProviderInstance>[
  AgentChatProviderInstance(id: 'codex', provider: 'codex', label: 'Codex'),
  AgentChatProviderInstance(
    id: 'cursor',
    provider: 'cursor',
    label: 'Cursor',
    available: false,
  ),
  AgentChatProviderInstance(
    id: 'claude',
    provider: 'claudeAgent',
    label: 'Claude',
  ),
];

AgentChatUsageFallback? _fallback(
  List<AgentChatUsageReading> readings, {
  List<AgentChatSelection?> explicit = const <AgentChatSelection?>[],
}) => agentChatUsageFallback(
  resolved: const AgentChatSelection(providerInstanceId: 'codex'),
  providers: _providers,
  explicit: explicit,
  limitOf: (provider) => agentChatUsageLimit(readings, provider, now: _now),
);

void main() {
  test('a provider is out of usage only while a full meter has not reset', () {
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[_reading('codex', 100)],
        'codex',
        now: _now,
      )?.resetsAt,
      _now.add(const Duration(hours: 1)),
    );
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[
          _reading('codex', 100, resetsIn: const Duration(hours: -1)),
        ],
        'codex',
        now: _now,
      ),
      isNull,
    );
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[_reading('codex', 99)],
        'codex',
        now: _now,
      ),
      isNull,
    );
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[_reading('codex', 100, fresh: false)],
        'codex',
        now: _now,
      ),
      isNull,
    );
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[_reading('claude', 100)],
        'claudeAgent',
        now: _now,
      ),
      isNotNull,
    );
  });

  test('one Claude account with usage left keeps the provider usable', () {
    expect(
      agentChatUsageLimit(
        <AgentChatUsageReading>[
          _reading('claude', 100),
          _reading('claude', 10),
        ],
        'claudeAgent',
        now: _now,
      ),
      isNull,
    );
  });

  test('falls back to the next available agent with usage left', () {
    final fallback = _fallback(<AgentChatUsageReading>[_reading('codex', 100)]);
    expect(fallback?.selection.providerInstanceId, 'claude');
    expect(fallback?.title, 'Using Claude');
    expect(fallback?.detail, 'Codex is out of usage');
    // "Use Codex" switches back to the agent the chat would have used.
    expect(fallback?.defaultSelection?.providerInstanceId, 'codex');
    expect(fallback?.useDefaultLabel, 'Use Codex');
  });

  test('Use names the default model when one was resolved', () {
    final fallback = agentChatUsageFallback(
      resolved: const AgentChatSelection(
        providerInstanceId: 'codex',
        model: 'gpt-5.5',
      ),
      providers: <AgentChatProviderInstance>[
        const AgentChatProviderInstance(
          id: 'codex',
          provider: 'codex',
          label: 'Codex',
          models: <AgentChatModelOption>[
            AgentChatModelOption(id: 'gpt-5.5', label: 'GPT-5.5'),
          ],
        ),
        ..._providers.skip(1),
      ],
      limitOf: (provider) => agentChatUsageLimit(
        <AgentChatUsageReading>[_reading('codex', 100)],
        provider,
        now: _now,
      ),
    );
    expect(fallback?.defaultSelection?.model, 'gpt-5.5');
    expect(fallback?.useDefaultLabel, 'Use GPT-5.5');
  });

  test('keeps the agent when it was chosen explicitly or data is missing', () {
    expect(
      _fallback(
        <AgentChatUsageReading>[_reading('codex', 100)],
        explicit: <AgentChatSelection?>[
          const AgentChatSelection(providerInstanceId: 'codex'),
        ],
      ),
      isNull,
    );
    expect(_fallback(const <AgentChatUsageReading>[]), isNull);
    expect(
      _fallback(<AgentChatUsageReading>[
        _reading('codex', 100),
        _reading('claude', 100),
      ]),
      isNull,
    );
  });
}

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

const _defaultModel = AgentChatModelOption(id: null, label: 'Provider Default');
const _providers = <AgentChatProviderInstance>[
  AgentChatProviderInstance(
    id: 'codex',
    provider: 'codex',
    label: 'Codex',
    models: <AgentChatModelOption>[_defaultModel],
  ),
  AgentChatProviderInstance(
    id: 'claude-work',
    provider: 'claudeAgent',
    label: 'Claude Work',
  ),
  AgentChatProviderInstance(
    id: 'off',
    provider: 'codex',
    label: 'Off',
    enabled: false,
  ),
  AgentChatProviderInstance(
    id: 'missing',
    provider: 'codex',
    label: 'Missing',
    available: false,
  ),
];

void main() {
  test('catalog preserves a nullable provider-default id', () {
    final instance = AgentChatProviderInstance.fromJson(<String, Object?>{
      'providerInstanceId': 'codex',
      'models': <Object?>[
        <String, Object?>{'id': null, 'label': 'Provider Default'},
      ],
    });
    expect(instance.models.single.id, isNull);
    expect(instance.modelById(null), instance.models.single);
    expect(instance.initialModel?.id, isNull);
    expect(
      AgentChatModelOption.fromJson(<String, Object?>{'id': ''}).id,
      isNull,
    );
  });

  test(
    'configure distinguishes omission from explicit model and effort reset',
    () {
      expect(const AgentChatConfiguration().toJson(), isEmpty);
      const reset = AgentChatConfiguration(
        resetModel: true,
        resetReasoningEffort: true,
      );
      expect(reset.isEmpty, isFalse);
      expect(reset.toJson(), <String, Object?>{
        'model': null,
        'reasoningEffort': null,
      });
      expect(
        const AgentChatConfiguration(model: '').toJson(),
        <String, Object?>{'model': null},
      );
      expect(
        const AgentChatConfiguration(model: 'gpt').toJson(),
        <String, Object?>{'model': 'gpt'},
      );
    },
  );

  test(
    'create and send omit provider default and never serialize empty model ids',
    () {
      final create = const AgentChatCreateInput(
        requestId: 'r',
        workspaceId: 'w',
        provider: 'codex',
        model: '',
      ).toJson();
      final send = const AgentChatSendInput(
        chatId: 'c',
        workspaceId: 'w',
        clientMessageId: 'm',
        text: 'hi',
        model: ' ',
      ).toJson();
      expect(create.containsKey('model'), isFalse);
      expect(send.containsKey('model'), isFalse);
      expect(
        const AgentChatSelection(providerInstanceId: 'codex')
            .configuration()
            .toJson(),
        <String, Object?>{'model': null},
      );
      expect(
        const AgentChatSelection(providerInstanceId: 'codex')
            .createInput(requestId: 'r', workspaceId: 'w')
            .toJson(),
        <String, Object?>{
          'requestId': 'r',
          'workspaceId': 'w',
          'providerInstanceId': 'codex',
        },
      );
    },
  );

  test('default resolution follows all five levels in order', () {
    const choices = <AgentChatSelection>[
      AgentChatSelection(providerInstanceId: 'claude-work', model: 'project'),
      AgentChatSelection(providerInstanceId: 'codex', model: 'launch'),
      AgentChatSelection(providerInstanceId: 'codex', model: 'explicit'),
      AgentChatSelection(providerInstanceId: 'codex', model: 'remembered'),
    ];
    for (var skipped = 0; skipped <= choices.length; skipped++) {
      final result = resolveAgentChatSelection(
        providers: _providers,
        projectDefault: skipped <= 0 ? choices[0] : null,
        launchingSelection: skipped <= 1 ? choices[1] : null,
        defaultSelection: skipped <= 2 ? choices[2] : null,
        rememberedSelection: skipped <= 3 ? choices[3] : null,
      );
      expect(
        result,
        skipped < choices.length
            ? choices[skipped]
            : const AgentChatSelection(providerInstanceId: 'codex'),
      );
    }
  });

  test(
    'default resolution skips disabled unavailable and removed instances',
    () {
      expect(
        resolveAgentChatSelection(
          providers: _providers,
          projectDefault: const AgentChatSelection(providerInstanceId: 'off'),
          launchingSelection: const AgentChatSelection(
            providerInstanceId: 'missing',
          ),
          defaultSelection: const AgentChatSelection(
            providerInstanceId: 'removed',
          ),
          rememberedSelection: const AgentChatSelection(
            providerInstanceId: 'claude-work',
            model: 'custom',
          ),
        ),
        const AgentChatSelection(
          providerInstanceId: 'claude-work',
          model: 'custom',
        ),
      );
      expect(
        resolveAgentChatSelection(providers: _providers.sublist(2)),
        isNull,
      );
    },
  );

  test('launching chat defaults are restricted to the same workspace', () {
    const preferences = AgentChatPreferences(
      defaultSelection: AgentChatSelection(
        providerInstanceId: 'codex',
        model: 'explicit',
      ),
    );
    const launch = AgentChatSelection(
      providerInstanceId: 'claude-work',
      model: 'launch',
    );
    expect(
      preferences.resolve(
        providers: _providers,
        workspaceId: 'w',
        launchingWorkspaceId: 'w',
        launchingSelection: launch,
      ),
      launch,
    );
    expect(
      preferences.resolve(
        providers: _providers,
        workspaceId: 'w',
        launchingWorkspaceId: 'other',
        launchingSelection: launch,
      ),
      preferences.defaultSelection,
    );
    expect(
      preferences.resolve(providers: _providers, launchingSelection: launch),
      preferences.defaultSelection,
    );
  });

  test('picker filters hidden rows but retains the current hidden model in configured order', () {
    const providers = <AgentChatProviderInstance>[
      AgentChatProviderInstance(
        id: 'codex',
        provider: 'codex',
        label: 'Codex Work',
        models: <AgentChatModelOption>[
          _defaultModel,
          AgentChatModelOption(id: 'a', label: 'Model Alpha'),
          AgentChatModelOption(id: 'b', label: 'Model Beta'),
          AgentChatModelOption(id: 'c', label: 'Model Gamma'),
        ],
      ),
    ];
    const preferences = AgentChatPreferences(
      models: <String, AgentChatModelPreferences>{
        'codex': AgentChatModelPreferences(
          hidden: <String>['a', 'b'],
          order: <String>['c', 'b', 'a'],
        ),
      },
    );
    final rows = agentChatPickerGroups(
      providers: providers,
      preferences: preferences,
      currentSelection: const AgentChatSelection(
        providerInstanceId: 'codex',
        model: 'b',
      ),
    ).single.rows;
    expect(rows.map((row) => row.model.id), <String?>['c', 'b', null]);
    expect(rows[1].selected, isTrue);
    expect(
      agentChatPickerGroups(
        providers: providers,
        query: 'work beta',
      ).single.rows.single.model.id,
      'b',
    );
    expect(
      agentChatPickerGroups(providers: providers, query: 'missing'),
      isEmpty,
    );
  });

  test(
    'unavailable rows remain visible and busy provider switches are disabled',
    () {
      final groups = agentChatPickerGroups(
        providers: _providers,
        currentSelection: const AgentChatSelection(providerInstanceId: 'codex'),
        canSwitchProvider: false,
        switchDisabledReason: 'A request is open.',
      );
      expect(groups.map((group) => group.instance.id), <String>[
        'codex',
        'claude-work',
        'missing',
      ]);
      expect(groups.first.rows.single.enabled, isTrue);
      expect(groups[1].rows.single.enabled, isFalse);
      expect(groups[1].rows.single.disabledReason, 'A request is open.');
      expect(
        groups[2].rows.single.disabledReason,
        'This provider is unavailable.',
      );
      final currentDisabled = agentChatPickerGroups(
        providers: _providers,
        currentSelection: const AgentChatSelection(
          providerInstanceId: 'off',
          model: 'custom',
        ),
      );
      expect(
        currentDisabled
            .singleWhere((group) => group.instance.id == 'off')
            .rows
            .last
            .selected,
        isTrue,
      );
    },
  );

  test('catalog availability does not imply verified sign-in', () {
    final instance = AgentChatProviderInstance.fromJson(<String, Object?>{
      'providerInstanceId': 'codex',
      'available': true,
    });
    expect(instance.auth.status, AgentChatProviderAuthStatus.unknown);
    expect(instance.auth.verified, isFalse);
    final verified = AgentChatProviderAuth.fromJson(<String, Object?>{
      'status': 'signedIn',
      'checkedAt': '2026-10-13T12:00:00Z',
    });
    expect(verified.verified, isTrue);
    expect(
      AgentChatProviderAuth.fromJson(<String, Object?>{'status': 'signedIn'})
          .verified,
      isFalse,
    );
  });
}

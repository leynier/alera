import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_model_rows.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const instance = AgentChatProviderInstance(
    id: 'codex',
    provider: 'codex',
    label: 'Codex',
    modelsSource: AgentChatModelsSource.discovered,
    models: <AgentChatModelOption>[
      AgentChatModelOption(
        id: null,
        label: 'Provider Default',
        isDefault: true,
      ),
      AgentChatModelOption(id: 'gpt-5.5', label: 'GPT-5.5'),
      AgentChatModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
      AgentChatModelOption(
        id: 'house-model',
        label: 'House Model',
        source: AgentChatModelsSource.configured,
      ),
    ],
  );

  AgentProviderModelList rows({
    AgentChatPreferences preferences = const AgentChatPreferences(),
    List<String> customModels = const <String>[],
    String query = '',
    String? defaultModel,
  }) => agentProviderModelRows(
    instance: instance,
    customModels: customModels,
    preferences: preferences,
    providerInstanceId: 'codex',
    defaultModel: defaultModel,
    query: query,
  );

  test('lists catalog, provider default and unsaved custom models once', () {
    final list = rows(customModels: const <String>['gpt-5.6-sol', 'mine']);
    expect(list.rows.map((row) => row.id), <String?>[
      null,
      'gpt-5.5',
      'gpt-5.6-sol',
      'house-model',
      'mine',
    ]);
    expect(list.rows[1].source, AgentProviderModelSource.discovered);
    expect(list.rows[2].source, AgentProviderModelSource.custom);
    expect(list.rows[3].source, AgentProviderModelSource.configured);
    expect(list.rows[4].source, AgentProviderModelSource.custom);
    expect(list.total, 5);
  });

  test('applies hidden, order, favorites and the instance default', () {
    final list = rows(
      defaultModel: 'gpt-5.6-sol',
      preferences: const AgentChatPreferences(
        models: <String, AgentChatModelPreferences>{
          'codex': AgentChatModelPreferences(
            hidden: <String>['gpt-5.5'],
            order: <String>['gpt-5.6-sol'],
          ),
        },
        favorites: <AgentChatSelection>[
          AgentChatSelection(providerInstanceId: 'codex', model: 'gpt-5.6-sol'),
          AgentChatSelection(providerInstanceId: 'claudeAgent'),
        ],
      ),
    );
    expect(list.rows.first.id, 'gpt-5.6-sol');
    expect(list.rows.first.favorite, isTrue);
    expect(list.rows.first.isDefault, isTrue);
    expect(list.rows.singleWhere((row) => row.id == 'gpt-5.5').hidden, isTrue);
    expect(list.hiddenCount, 1);
    expect(list.visibleCount, 3);
    // The provider default can never be hidden.
    expect(list.rows.singleWhere((row) => row.id == null).canHide, isFalse);
  });

  test('without an instance default the provider default row is default', () {
    final list = rows();
    expect(
      list.rows.where((row) => row.isDefault).map((row) => row.id),
      <String?>[null],
    );
  });

  test('an instance default unmarks the provider default row', () {
    final list = rows(defaultModel: 'gpt-5.5');
    expect(
      list.rows.where((row) => row.isDefault).map((row) => row.id),
      <String?>['gpt-5.5'],
    );
  });

  test('movable bounds skip the provider default row', () {
    // The catalog lists the provider default first.
    final leading = rows();
    expect(leading.rows.first.id, isNull);
    expect(leading.firstMovableId, 'gpt-5.5');
    expect(leading.lastMovableId, 'house-model');

    // Without a catalog entry the provider default is appended last, so the
    // last identified model is still the end of the order.
    final appended = agentProviderModelRows(
      instance: const AgentChatProviderInstance(
        id: 'codex',
        provider: 'codex',
        label: 'Codex',
        models: <AgentChatModelOption>[
          AgentChatModelOption(id: 'a', label: 'A'),
          AgentChatModelOption(id: 'b', label: 'B'),
        ],
      ),
      customModels: const <String>[],
      preferences: const AgentChatPreferences(),
      providerInstanceId: 'codex',
    );
    expect(appended.rows.map((row) => row.id), <String?>['a', 'b', null]);
    expect(appended.firstMovableId, 'a');
    expect(appended.lastMovableId, 'b');
  });

  test('an unset model names the instance default when one is set', () {
    final list = rows().rows;
    expect(agentProviderUnsetModelLabel(list, null), 'Provider Default');
    expect(
      agentProviderUnsetModelLabel(list, 'gpt-5.6-sol'),
      'Instance Default (GPT-5.6 Sol)',
    );
    // An id the list does not know still names itself.
    expect(
      agentProviderUnsetModelLabel(list, 'retired-model'),
      'Instance Default (retired-model)',
    );
  });

  test('a query filters rows but not the counts', () {
    final list = rows(query: 'sol');
    expect(list.rows.map((row) => row.id), <String?>['gpt-5.6-sol']);
    expect(list.total, 4);
  });

  test('hiding and showing rewrite only that id', () {
    const current = AgentChatModelPreferences(
      hidden: <String>['a'],
      order: <String>['b', 'a'],
    );
    final hidden = agentProviderSetModelHidden(current, 'b', hidden: true);
    expect(hidden.hidden, <String>['a', 'b']);
    expect(hidden.order, <String>['b', 'a']);
    final shown = agentProviderSetModelHidden(hidden, 'a', hidden: false);
    expect(shown.hidden, <String>['b']);
  });

  test('moving stores the full displayed order without the default', () {
    final moved = agentProviderMoveModel(
      const AgentChatModelPreferences(),
      const <String?>[null, 'a', 'b', 'c'],
      'c',
      -1,
    );
    expect(moved.order, <String>['a', 'c', 'b']);
    final unchanged = agentProviderMoveModel(
      moved,
      const <String?>['a', 'c', 'b'],
      'a',
      -1,
    );
    expect(identical(unchanged, moved), isTrue);
  });

  test('favorites toggle one instance and model pair', () {
    const existing = <AgentChatSelection>[
      AgentChatSelection(providerInstanceId: 'codex', model: 'a'),
      AgentChatSelection(providerInstanceId: 'pi', model: 'a'),
    ];
    final removed = agentProviderSetFavorite(
      existing,
      providerInstanceId: 'codex',
      model: 'a',
      favorite: false,
    );
    expect(removed, const <AgentChatSelection>[
      AgentChatSelection(providerInstanceId: 'pi', model: 'a'),
    ]);
    final added = agentProviderSetFavorite(
      removed,
      providerInstanceId: 'codex',
      model: null,
      favorite: true,
    );
    expect(added.last, const AgentChatSelection(providerInstanceId: 'codex'));
  });
}

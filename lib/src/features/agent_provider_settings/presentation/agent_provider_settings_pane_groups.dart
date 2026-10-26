part of 'agent_provider_settings_pane.dart';

extension _AgentProviderPaneGroups on _AgentProviderSettingsPaneState {
  AgentProviderDefaultsGroup _defaultsGroup(
    AgentProviderEntry entry,
    AgentProviderInstanceDraft draft,
    String title,
    AgentChatPreferences? preferences,
    bool editable,
  ) {
    final projects = ref.watch(agentProviderProjectsProvider);
    final projectDefaults =
        preferences?.projectDefaults ?? const <String, AgentChatSelection>{};
    final defaultSelection = preferences?.defaultSelection;
    final isDefault = defaultSelection?.providerInstanceId == entry.id;
    final rows = agentProviderModelRows(
      instance: entry.catalog,
      customModels: draft.customModels,
      preferences: preferences ?? const AgentChatPreferences(),
      providerInstanceId: entry.id,
    ).rows;
    // A hidden model stays choosable while it is the current default, so the
    // dropdown never shows a value it cannot list. Naming no model means the
    // instance's configured default, so that row says which one it is.
    final unsetLabel = agentProviderUnsetModelLabel(rows, draft.defaultModel);
    final models = <AgentProviderModelChoice>[
      for (final model in rows)
        if (!model.hidden || (isDefault && model.id == defaultSelection?.model))
          AgentProviderModelChoice(
            id: model.id,
            label: model.id == null ? unsetLabel : model.label,
          ),
    ];
    return AgentProviderDefaultsGroup(
      instanceLabel: title,
      isDefault: isDefault,
      defaultModel: isDefault ? defaultSelection?.model : null,
      models: models,
      editable: editable && !entry.unsaved,
      instanceEnabled: entry.enabled,
      unavailableReason: preferences == null
          ? 'The Alera runtime needs an update before defaults can be '
                'changed here.'
          : entry.unsaved
          ? 'Save this provider before making it a default.'
          : null,
      projectDefaults: <AgentProviderProjectDefault>[
        for (final project in projects)
          if (projectDefaults[project.id] case final selection?
              when selection.providerInstanceId == entry.id)
            AgentProviderProjectDefault(
              projectId: project.id,
              projectName: project.name,
              model: selection.model,
            ),
      ],
      otherProjects: <({String id, String name})>[
        for (final project in projects)
          if (projectDefaults[project.id]?.providerInstanceId != entry.id)
            project,
      ],
      onSetDefault: (use, model) => unawaited(
        _updatePreferences(
          (_) => <AgentChatPreferenceOperation>[
            AgentChatSetDefaultSelection(
              use
                  ? AgentChatSelection(
                      providerInstanceId: entry.id,
                      model: model,
                    )
                  : null,
            ),
          ],
        ),
      ),
      onSetProjectDefault: (projectId, model) => unawaited(
        _updatePreferences(
          (_) => <AgentChatPreferenceOperation>[
            AgentChatSetProjectDefault(
              projectId: projectId,
              selection: AgentChatSelection(
                providerInstanceId: entry.id,
                model: model,
              ),
            ),
          ],
        ),
      ),
      onClearProjectDefault: (projectId) => unawaited(
        _updatePreferences(
          (_) => <AgentChatPreferenceOperation>[
            AgentChatSetProjectDefault(projectId: projectId, selection: null),
          ],
        ),
      ),
    );
  }

  AgentProviderModelsGroup _modelsGroup(
    AgentProviderEntry entry,
    AgentProviderInstanceDraft draft,
    AgentChatPreferences? preferences,
    bool preferencesEditable,
    bool launchEditable,
  ) {
    final list = agentProviderModelRows(
      instance: entry.catalog,
      customModels: draft.customModels,
      preferences: preferences ?? const AgentChatPreferences(),
      providerInstanceId: entry.id,
      defaultModel: draft.defaultModel,
      query: _modelQuery,
    );
    final source =
        entry.catalog?.modelsSource ?? AgentChatModelsSource.providerDefault;
    return AgentProviderModelsGroup(
      models: list,
      sourceLabel: agentChatModelsSourceLabel(source),
      query: _modelQuery,
      onQueryChanged: (value) => _update(() => _modelQuery = value.trim()),
      preferencesEditable: preferencesEditable && !entry.unsaved,
      launchEditable: launchEditable,
      preferencesUnavailableReason: preferences == null
          ? 'Visibility, order and favorites need a newer Alera runtime.'
          : entry.unsaved
          ? 'Save this provider to hide, order or favorite its models.'
          : null,
      onSetHidden: (id, hidden) =>
          unawaited(_setModelHidden(entry.id, id, hidden)),
      onSetFavorite: (id, favorite) =>
          unawaited(_setFavorite(entry.id, id, favorite)),
      onMove: (id, delta) => unawaited(
        _moveModel(
          entry.id,
          <String?>[for (final row in list.rows) row.id],
          id,
          delta,
        ),
      ),
      onMakeDefault: (id) => _edit(
        id == null
            ? draft.copyWith(resetDefaultModel: true)
            : draft.copyWith(defaultModel: id),
      ),
      onAddCustom: (id) {
        if (draft.customModels.contains(id)) {
          return;
        }
        _edit(
          draft.copyWith(customModels: <String>[...draft.customModels, id]),
        );
      },
      onRemoveCustom: (id) => _edit(
        draft.copyWith(
          customModels: <String>[
            for (final model in draft.customModels)
              if (model != id) model,
          ],
          resetDefaultModel: draft.defaultModel == id,
        ),
      ),
    );
  }
}

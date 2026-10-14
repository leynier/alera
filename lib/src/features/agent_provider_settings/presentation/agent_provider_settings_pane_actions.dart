part of 'agent_provider_settings_pane.dart';

enum _LeaveChoice { save, discard }

extension _AgentProviderPaneActions on _AgentProviderSettingsPaneState {
  /// Seeds the editor for [entry] on the first build after a selection, and
  /// later only when the host's stored state moved: an untouched draft takes
  /// the new state, an edited one keeps the edits and says so. The enabled
  /// flag always follows the host, because the list switch writes it at once.
  void _seed(AgentProviderEntry entry, {required bool snapshotLoaded}) {
    final key = '${_hostId ?? ''}/${entry.id}';
    final seed = entry.seed();
    final baseline = _baseline;
    final draft = _draft;
    if (_baselineKey != key || baseline == null || draft == null) {
      _baselineKey = key;
      _baseline = seed;
      _draft = seed;
      _changedElsewhere = false;
      _secrets.clear();
      _error = null;
      _modelQuery = '';
      return;
    }
    if (!snapshotLoaded || seed.isNew) {
      return;
    }
    // The enable switch writes at once and may create the override row, so
    // neither counts as someone else's edit.
    final moved =
        seed.copyWith(enabled: baseline.enabled).signature !=
        baseline.signature;
    final edited = draft.signature != baseline.signature;
    String savedSecrets(AgentProviderInstanceDraft value) => <String>[
      for (final entry in value.environment)
        if (entry.secretSaved) entry.name,
      ...value.savedSecretOptions,
    ].join('\u0000');
    final reseed =
        moved ||
        seed.hasOverride != baseline.hasOverride ||
        savedSecrets(seed) != savedSecrets(baseline);
    if (reseed && !edited && _secrets.isEmpty) {
      _baseline = seed;
      _draft = seed;
      return;
    }
    if (moved) {
      _changedElsewhere = true;
    }
    if (seed.enabled != baseline.enabled) {
      _baseline = baseline.copyWith(enabled: seed.enabled);
      _draft = draft.copyWith(enabled: seed.enabled);
    }
  }

  Future<void> _selectHost(String? hostId) async {
    if (hostId == _hostId || !await _leave()) {
      return;
    }
    if (mounted) {
      _update(() {
        _hostId = hostId;
        _wantedHostId = null;
        _unsavedNew = null;
        _baselineKey = null;
        _selectedId = null;
      });
    }
  }

  Future<void> _selectRow(String id) async {
    if (id == _selectedId || !await _leave()) {
      return;
    }
    if (mounted) {
      _update(() => _selectedId = id);
    }
  }

  Future<void> _closeAfterLeaving() async {
    if (await _leave() && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Whether the person may leave the current draft: true when nothing is
  /// unsaved, or once they saved or discarded it.
  Future<bool> _leave() async {
    if (!_dirty) {
      return true;
    }
    final title = _draft?.label.trim().isNotEmpty ?? false
        ? _draft!.label.trim()
        : 'This provider';
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (_) => AleraChoiceDialog<_LeaveChoice>(
        title: 'Save Changes?',
        message: '$title has unsaved changes.',
        primaryLabel: 'Save',
        primaryValue: _LeaveChoice.save,
        secondaryLabel: 'Discard',
        secondaryValue: _LeaveChoice.discard,
        destructiveSecondary: true,
        cancelLabel: 'Keep Editing',
      ),
    );
    switch (choice) {
      case _LeaveChoice.save:
        return _save();
      case _LeaveChoice.discard:
        _revert();
        return true;
      case null:
        return false;
    }
  }

  Future<void> _refresh() => ref
      .read(agentProviderCatalogControllerProvider(_hostId).notifier)
      .refresh();

  Future<void> _addProvider(List<AgentProviderEntry> entries) async {
    if (!await _leave() || !mounted) {
      return;
    }
    final draft = await showAddAgentProviderDialog(
      context,
      takenIds: <String>{for (final entry in entries) entry.id},
    );
    if (draft == null || !mounted) {
      return;
    }
    _update(() {
      _unsavedNew = draft;
      _selectedId = draft.providerInstanceId;
      _baselineKey = null;
    });
  }

  /// Saves the draft and its pending secrets. Returns whether everything
  /// applied; on failure the draft and the secrets that did not apply stay.
  Future<bool> _save() async {
    final draft = _draft;
    final baseline = _baseline;
    if (draft == null || baseline == null || _saving) {
      return false;
    }
    _update(() {
      _saving = true;
      _error = null;
    });
    final secrets = _secrets.values.toList();
    try {
      await ref
          .read(agentProviderSettingsControllerProvider(_hostId).notifier)
          .save(
            draft: draft,
            saved: baseline.hasOverride ? baseline : null,
            secrets: secrets,
          );
      if (!mounted) {
        return true;
      }
      _update(() {
        _saving = false;
        _secrets.clear();
        _unsavedNew = null;
        _selectedId = draft.providerInstanceId;
        _baselineKey = null;
      });
      AleraToast.show(
        context,
        message: draft.isNew ? 'Provider added' : 'Provider saved',
        tone: .success,
      );
      return true;
    } on AgentProviderSettingsFailure catch (failure) {
      if (mounted) {
        _update(() {
          _saving = false;
          _error = failure.message;
          if (failure.kind == .revisionConflict) {
            _changedElsewhere = true;
          }
        });
      }
      return false;
    }
  }

  Future<void> _setEnabled(AgentProviderEntry entry, bool enabled) async {
    try {
      await ref
          .read(agentProviderSettingsControllerProvider(_hostId).notifier)
          .setEnabled(
            providerInstanceId: entry.id,
            provider: entry.provider,
            enabled: enabled,
          );
    } on AgentProviderSettingsFailure catch (failure) {
      if (mounted) {
        AleraToast.show(
          context,
          message: failure.message,
          tone: .error,
          duration: AleraToast.longDuration,
        );
      }
    }
  }

  Future<void> _remove(AgentProviderEntry entry, String title) async {
    final controller = ref.read(
      agentProviderSettingsControllerProvider(_hostId).notifier,
    );
    _update(() {
      _saving = true;
      _error = null;
    });
    try {
      final builtIn = entry.id == entry.provider;
      // Resetting a built-in never strands a chat, so only an added
      // instance asks the host which chats use it.
      final impact = builtIn
          ? AgentChatProviderRemovalImpact(providerInstanceId: entry.id)
          : await controller.removalImpact(entry.id);
      if (!mounted) {
        return;
      }
      _update(() => _saving = false);
      final confirmed = await confirmAgentProviderRemoval(
        context,
        label: title,
        builtIn: builtIn,
        impact: impact,
      );
      if (!confirmed || !mounted) {
        return;
      }
      _update(() => _saving = true);
      await controller.remove(
        entry.id,
        allowInUse: !builtIn && impact.count > 0,
      );
      if (!mounted) {
        return;
      }
      _update(() {
        _saving = false;
        _secrets.clear();
        _baselineKey = null;
        if (entry.id != entry.provider) {
          _selectedId = null;
        }
      });
    } on AgentProviderSettingsFailure catch (failure) {
      if (mounted) {
        _update(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  /// Runs a setup action in a terminal on This Device, then checks the
  /// provider again, whatever happened there. Only the instance id and the
  /// action leave this pane: the host resolves the verified recipe, with the
  /// instance's own profile and credentials, so a custom instance can never
  /// sign in through another instance's account.
  Future<void> _runSetup(
    String providerInstanceId,
    AgentChatProviderSetupCommand command,
    String title,
  ) async {
    if (_hostId != null) {
      return;
    }
    await showCommandTerminalDialog(
      context,
      ref,
      CommandTerminalRequest(
        title: '${command.label}: $title',
        command: command.label,
        description: 'Alera checks $title again when you close this terminal.',
        providerSetup: CommandTerminalProviderSetup(
          providerInstanceId: providerInstanceId,
          action: command.action,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  /// Applies preference operations built from the latest preferences, so a
  /// concurrent change on the phone is merged rather than overwritten.
  Future<void> _updatePreferences(
    List<AgentChatPreferenceOperation> Function(AgentChatPreferences latest)
    operations,
  ) async {
    final hostId = _hostId;
    final current = ref.read(agentChatPreferencesProvider(hostId)).value;
    if (current == null) {
      return;
    }
    try {
      await ref
          .read(agentProviderPreferencesWriterProvider(hostId))
          .update(current, operations);
    } on AgentProviderSettingsFailure catch (failure) {
      if (mounted) {
        AleraToast.show(
          context,
          message: failure.message,
          tone: .error,
          duration: AleraToast.longDuration,
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(agentChatPreferencesProvider(hostId));
      }
    }
  }

  Future<void> _setModelHidden(String instanceId, String id, bool hidden) =>
      _updatePreferences(
        (latest) => <AgentChatPreferenceOperation>[
          AgentChatSetModelPreferences(
            providerInstanceId: instanceId,
            preferences: agentProviderSetModelHidden(
              latest.models[instanceId] ?? const AgentChatModelPreferences(),
              id,
              hidden: hidden,
            ),
          ),
        ],
      );

  Future<void> _moveModel(
    String instanceId,
    List<String?> displayed,
    String id,
    int delta,
  ) => _updatePreferences(
    (latest) => <AgentChatPreferenceOperation>[
      AgentChatSetModelPreferences(
        providerInstanceId: instanceId,
        preferences: agentProviderMoveModel(
          latest.models[instanceId] ?? const AgentChatModelPreferences(),
          displayed,
          id,
          delta,
        ),
      ),
    ],
  );

  Future<void> _setFavorite(String instanceId, String? model, bool favorite) =>
      _updatePreferences(
        (latest) => <AgentChatPreferenceOperation>[
          AgentChatSetFavorites(
            agentProviderSetFavorite(
              latest.favorites,
              providerInstanceId: instanceId,
              model: model,
              favorite: favorite,
            ),
          ),
        ],
      );
}

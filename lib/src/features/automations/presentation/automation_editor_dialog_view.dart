part of 'automation_editor_dialog.dart';

extension on _AutomationEditorDialogState {
  Widget _buildEditor(BuildContext context) {
    final projects =
        ref.watch(projectListProvider).asData?.value ?? const <Project>[];
    final profiles =
        ref.watch(agentProfilesProvider).asData?.value ??
        const <AgentProfile>[];
    final workbench = ref.watch(workbenchControllerProvider);
    final projectId = _projectId.text.trim();
    final workspaces = workbench.workspacesByProject.values
        .expand((items) => items)
        .where(
          (workspace) => projectId.isEmpty || workspace.projectId == projectId,
        )
        .toList(growable: false);
    final checkouts = ref.watch(automationProjectCheckoutsProvider(projectId));
    final workspaceId = _workspaceId.text.trim();
    final tabs = workspaceId.isEmpty
        ? const <WorkspaceTabRecord>[]
        : workbench.tabsFor(workspaceId);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              widget.initial == null ? 'New Automation' : 'Edit Automation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.space16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    _text(_name, 'Name'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_slug, 'Slug'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_description, 'Description', maxLines: 3),
                    const SizedBox(height: AleraTokens.space12),
                    _idPicker(
                      controller: _projectId,
                      label: _targetKind == 'projectCheckout'
                          ? 'Project'
                          : 'Project (Optional)',
                      optional: _targetKind != 'projectCheckout',
                      options: [
                        for (final project in projects)
                          (id: project.id, label: project.name),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_tagIds, 'Tag Ids (Comma-separated)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_prompt, 'Prompt Template', maxLines: 5),
                    const SizedBox(height: AleraTokens.space12),
                    _dropdown(
                      label: 'Schedule',
                      value: _scheduleKind,
                      values: const <String>['recurring', 'oneTime'],
                      onChanged: (value) =>
                          _refresh(() => _scheduleKind = value!),
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    if (_scheduleKind == 'recurring')
                      _text(_cron, 'Five-field Cron'),
                    if (_scheduleKind == 'oneTime') _text(_at, 'Run At (UTC)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_timezone, 'IANA Timezone'),
                    if (_scheduleKind == 'recurring') ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      _text(_startAt, 'Start At (Optional ISO-8601 UTC)'),
                      const SizedBox(height: AleraTokens.space12),
                      _text(_endAt, 'End At (Optional ISO-8601 UTC)'),
                      const SizedBox(height: AleraTokens.space12),
                      _text(
                        _maxScheduledRuns,
                        'Maximum Scheduled Runs (Optional)',
                      ),
                    ],
                    const SizedBox(height: AleraTokens.space12),
                    _dropdown(
                      label: 'Target',
                      value: _targetKind,
                      values: const <String>[
                        'existingTab',
                        'freshTab',
                        'managedWorkspace',
                        'projectCheckout',
                      ],
                      onChanged: (value) =>
                          _refresh(() => _targetKind = value!),
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    if (_targetKind != 'projectCheckout')
                      _idPicker(
                        controller: _workspaceId,
                        label: _targetKind == 'managedWorkspace'
                            ? 'Source Workspace'
                            : 'Workspace',
                        options: [
                          for (final workspace in workspaces)
                            (id: workspace.id, label: workspace.name),
                        ],
                      ),
                    if (_targetKind == 'projectCheckout') ...[
                      _idPicker(
                        controller: _checkoutHostId,
                        label: 'Project Folder',
                        options: [
                          for (final checkout
                              in checkouts.asData?.value ??
                                  const <({String hostId, String path})>[])
                            (
                              id: checkout.hostId,
                              label: '${checkout.hostId}: ${checkout.path}',
                            ),
                        ],
                      ),
                      if (checkouts.hasError)
                        const Text(
                          'Could not load project folders. Retry after checking the runtime connection.',
                        ),
                      const SizedBox(height: AleraTokens.space12),
                      _text(_nameTemplate, 'Workspace Name Template'),
                      const Text(
                        'Each run creates a new workspace on this folder using its current branch and files. Files are shared with other tasks.',
                      ),
                    ],
                    if (_targetKind == 'existingTab') ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      _idPicker(
                        controller: _tabId,
                        label: 'Tab',
                        options: [
                          for (final tab in tabs)
                            (id: tab.id, label: tab.title),
                        ],
                      ),
                      const SizedBox(height: AleraTokens.space12),
                      _text(
                        _conversationId,
                        'Agent Conversation ID (Optional)',
                      ),
                    ],
                    if (_targetKind != 'existingTab') ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      _idPicker(
                        controller: _profileId,
                        label: 'Agent Profile',
                        options: [
                          for (final profile in profiles)
                            (id: profile.id, label: profile.name),
                        ],
                      ),
                    ],
                    if (_targetKind == 'managedWorkspace') ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      _text(_sourceBranch, 'Source Branch'),
                      const SizedBox(height: AleraTokens.space12),
                      _text(_nameTemplate, 'Workspace Name Template'),
                    ],
                    const SizedBox(height: AleraTokens.space12),
                    _text(_precheck, 'Precheck Command (Optional)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_precheckTimeout, 'Precheck Timeout (Seconds)'),
                    const SizedBox(height: AleraTokens.space12),
                    Row(
                      children: <Widget>[
                        if (_targetKind != 'projectCheckout')
                          Expanded(
                            child: _dropdown(
                              label: 'Setup',
                              value: _setupPolicy,
                              values: const <String>[
                                'wait',
                                'parallel',
                                'skip',
                              ],
                              onChanged: (value) =>
                                  _refresh(() => _setupPolicy = value!),
                            ),
                          ),
                        if (_targetKind != 'projectCheckout')
                          const SizedBox(width: AleraTokens.space12),
                        Expanded(
                          child: _dropdown(
                            label: 'Overlap',
                            value: _overlapPolicy,
                            values: const <String>[
                              'skip',
                              'runLatestOnce',
                              'queue',
                              'forceParallel',
                            ],
                            onChanged: (value) =>
                                _refresh(() => _overlapPolicy = value!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _dropdown(
                            label: 'Misfire',
                            value: _misfirePolicy,
                            values: const <String>[
                              'skip',
                              'runLatestOnce',
                              'queue',
                            ],
                            onChanged: (value) =>
                                _refresh(() => _misfirePolicy = value!),
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space12),
                        Expanded(
                          child: _dropdown(
                            label: 'Cleanup',
                            value: _cleanupPolicy,
                            values: const <String>['preserve', 'onSuccess'],
                            onChanged: (value) =>
                                _refresh(() => _cleanupPolicy = value!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_misfireGrace, 'Misfire Grace (Seconds)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_queueCap, 'Queue Cap (Maximum 10)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_inactivityTimeout, 'Inactivity Timeout (Seconds)'),
                    const SizedBox(height: AleraTokens.space12),
                    _text(_heartbeatInterval, 'Heartbeat Interval (Seconds)'),
                    const SizedBox(height: AleraTokens.space12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _text(
                            _retryMaxAttempts,
                            'Retry Attempts (Maximum 3)',
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space12),
                        Expanded(
                          child: _text(
                            _retryBackoff,
                            'Retry Backoff (Seconds)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _text(
                            _circuitThreshold,
                            'Circuit Failure Threshold',
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space12),
                        Expanded(
                          child: _text(_circuitOpen, 'Circuit Open (Seconds)'),
                        ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notify On Success'),
                      value: _notifyOnSuccess,
                      onChanged: (value) =>
                          _refresh(() => _notifyOnSuccess = value),
                    ),
                    if (_error case final error?) ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        error,
                        style: const TextStyle(color: AleraTokens.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save Automation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

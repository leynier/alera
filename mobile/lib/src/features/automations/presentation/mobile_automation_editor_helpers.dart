part of 'mobile_automation_editor.dart';

Widget _buildMobileAutomationEditor(
  _MobileAutomationEditorState state,
  BuildContext context,
) {
  final bottom = MediaQuery.viewInsetsOf(context).bottom;
  return Padding(
    padding: EdgeInsets.fromLTRB(
      AleraTokens.spaceMd,
      AleraTokens.spaceMd,
      AleraTokens.spaceMd,
      bottom + AleraTokens.spaceMd,
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              state.widget.initial == null
                  ? 'New Automation'
                  : 'Edit Automation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            state._field(state._name, 'Name'),
            state._field(state._slug, 'Slug'),
            state._field(state._description, 'Description', maxLines: 3),
            _choiceField(
              state._project,
              'Project (Optional)',
              state.widget.options?.projects
                      .map(
                        (project) => MobileAutomationChoice(
                          id: project.id,
                          label: project.name,
                        ),
                      )
                      .toList(growable: false) ??
                  const <MobileAutomationChoice>[],
              optional: true,
            ),
            state._field(state._tagIds, 'Tag Ids (Comma-separated)'),
            state._field(state._prompt, 'Prompt Template', maxLines: 4),
            state._dropdown('Schedule', state._scheduleKind, const <String>[
              'recurring',
              'oneTime',
            ], (value) => state._refresh(() => state._scheduleKind = value!)),
            if (state._scheduleKind == 'recurring')
              state._field(state._cron, 'Five-field Cron'),
            if (state._scheduleKind == 'oneTime')
              state._field(state._at, 'Run At (ISO-8601 UTC)'),
            state._field(state._timezone, 'IANA Timezone'),
            if (state._scheduleKind == 'recurring') ...<Widget>[
              state._field(state._startAt, 'Start At (Optional ISO-8601 UTC)'),
              state._field(state._endAt, 'End At (Optional ISO-8601 UTC)'),
              state._field(
                state._maxScheduledRuns,
                'Maximum Scheduled Runs (Optional)',
              ),
            ],
            _choiceField(
              state._workspace,
              'Workspace',
              state.widget.options?.workspaces
                      .map(
                        (workspace) => MobileAutomationChoice(
                          id: workspace.id,
                          label: '${workspace.name} (${workspace.projectId})',
                        ),
                      )
                      .toList(growable: false) ??
                  const <MobileAutomationChoice>[],
              onChanged: () => state._refresh(() {}),
            ),
            state._dropdown('Target', state._targetKind, const <String>[
              'existingTab',
              'freshTab',
              'managedWorkspace',
            ], (value) => state._refresh(() => state._targetKind = value!)),
            if (state._targetKind != 'existingTab')
              _choiceField(
                state._profile,
                'Agent Profile',
                state.widget.options?.profiles
                        .map(
                          (profile) => MobileAutomationChoice(
                            id: profile.id,
                            label: '${profile.name} (${profile.agentType})',
                          ),
                        )
                        .toList(growable: false) ??
                    const <MobileAutomationChoice>[],
              ),
            if (state._targetKind == 'existingTab') ...<Widget>[
              _choiceField(
                state._tab,
                'Tab',
                state.widget.options?.tabsFor(state._workspace.text.trim()) ??
                    const <MobileAutomationChoice>[],
              ),
              state._field(state._conversation, 'Agent Conversation ID'),
            ],
            if (state._targetKind == 'managedWorkspace') ...<Widget>[
              state._field(state._sourceBranch, 'Source Branch'),
              state._field(state._nameTemplate, 'Workspace Name Template'),
            ],
            state._field(
              state._precheck,
              'Precheck Command (Optional)',
              maxLines: 2,
            ),
            state._field(state._precheckTimeout, 'Precheck Timeout (Seconds)'),
            state._dropdown('Setup', state._setup, const <String>[
              'wait',
              'parallel',
              'skip',
            ], (value) => state._refresh(() => state._setup = value!)),
            state._dropdown('Overlap', state._overlap, const <String>[
              'skip',
              'queue',
              'runLatestOnce',
              'forceParallel',
            ], (value) => state._refresh(() => state._overlap = value!)),
            state._dropdown('Misfire', state._misfire, const <String>[
              'skip',
              'runLatestOnce',
              'queue',
            ], (value) => state._refresh(() => state._misfire = value!)),
            state._dropdown('Cleanup', state._cleanup, const <String>[
              'preserve',
              'onSuccess',
            ], (value) => state._refresh(() => state._cleanup = value!)),
            state._field(state._queueCap, 'Queue Cap (Maximum 10)'),
            state._field(
              state._inactivityTimeout,
              'Inactivity Timeout (Seconds)',
            ),
            state._field(
              state._heartbeatInterval,
              'Heartbeat Interval (Seconds)',
            ),
            state._field(state._misfireGrace, 'Misfire Grace (Seconds)'),
            state._field(state._retryMaxAttempts, 'Retry Attempts (Maximum 3)'),
            state._field(state._retryBackoff, 'Retry Backoff (Seconds)'),
            state._field(state._circuitThreshold, 'Circuit Failure Threshold'),
            state._field(state._circuitOpen, 'Circuit Open (Seconds)'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify On Success'),
              value: state._notifySuccess,
              onChanged: (value) =>
                  state._refresh(() => state._notifySuccess = value),
            ),
            if (state._error case final error?)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: AleraTokens.spaceSm),
            FilledButton(
              onPressed: state._save,
              child: const Text('Save Automation'),
            ),
          ],
        ),
      ),
    ),
  );
}

class const MobileAutomationChoice({
  required final String id,
  required final String label,
});

class const MobileAutomationEditorOptions({
  required final List<ProjectSummary> projects,
  required final List<WorkspaceSummary> workspaces,
  required final List<AgentProfileSummary> profiles,
  required final List<WorkspaceTabSummary> tabs,
}) {
  List<MobileAutomationChoice> tabsFor(String workspaceId) => tabs
      .where((tab) => tab.workspaceId == workspaceId)
      .map(
        (tab) => MobileAutomationChoice(
          id: tab.id,
          label: '${tab.displayTitle} (${tab.kind})',
        ),
      )
      .toList(growable: false);
}

Future<MobileAutomationEditorOptions> loadMobileAutomationEditorOptions(
  MobileRuntimeClient client,
) async {
  final projects = await client.listProjects();
  final workspaces = await client.listWorkspaces();
  final profiles = await client.listAgentProfiles();
  final tabLists = await Future.wait<List<WorkspaceTabSummary>>(
    workspaces.map((workspace) => client.listTabs(workspace.id)),
  );
  return MobileAutomationEditorOptions(
    projects: projects,
    workspaces: workspaces,
    profiles: profiles,
    tabs: <WorkspaceTabSummary>[for (final tabs in tabLists) ...tabs],
  );
}

Map<String, Object?> _map(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : <String, Object?>{};

Map<String, Object?>? _nested(Map<String, Object?>? map, String? key) {
  final value = key == null ? null : map?[key];
  return value is Map ? _map(value) : null;
}

String? _firstKey(Map<String, Object?>? map) =>
    map == null || map.isEmpty ? null : map.keys.first;

String _string(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _promptTemplateError(String template) {
  const known = <String>{
    'automation.id',
    'automation.name',
    'automation.slug',
    'run.id',
    'run.number',
    'run.scheduledAt',
    'workspace.id',
    'workspace.name',
    'workspace.path',
    'project.id',
    'project.name',
  };
  var cursor = 0;
  while (true) {
    final start = template.indexOf('{{', cursor);
    if (start < 0) {
      if (template.indexOf('}}', cursor) >= 0) {
        return 'Prompt template contains an unmatched closing delimiter.';
      }
      return null;
    }
    final end = template.indexOf('}}', start + 2);
    if (end < 0) {
      return 'Prompt template contains an unterminated variable.';
    }
    final variable = template.substring(start + 2, end).trim();
    if (!known.contains(variable)) {
      return 'Unknown prompt variable: {{$variable}}';
    }
    cursor = end + 2;
  }
}

Widget _choiceField(
  TextEditingController controller,
  String label,
  List<MobileAutomationChoice> choices, {
  bool optional = false,
  VoidCallback? onChanged,
}) {
  final current = controller.text.trim();
  final hasCurrent = choices.any((choice) => choice.id == current);
  final visibleChoices = <MobileAutomationChoice>[
    ...choices,
    if (current.isNotEmpty && !hasCurrent)
      MobileAutomationChoice(id: current, label: '$current (Current)'),
  ];
  return Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
    child: DropdownButtonFormField<String>(
      initialValue: current.isEmpty
          ? (optional ? '' : null)
          : hasCurrent || visibleChoices.any((choice) => choice.id == current)
          ? current
          : null,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        if (optional)
          const DropdownMenuItem<String>(value: '', child: Text('None')),
        for (final choice in visibleChoices)
          DropdownMenuItem<String>(value: choice.id, child: Text(choice.label)),
      ],
      onChanged: (value) {
        controller.text = value ?? '';
        onChanged?.call();
      },
    ),
  );
}

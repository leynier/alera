import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

part 'automation_editor_dialog_form.dart';

Future<JsonMap?> showAutomationEditorDialog(
  BuildContext context, {
  AutomationRecord? initial,
}) {
  return showDialog<JsonMap>(
    context: context,
    builder: (_) => AutomationEditorDialog(initial: initial),
  );
}

class const AutomationEditorDialog({super.key, final AutomationRecord? initial})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<AutomationEditorDialog> createState() =>
      _AutomationEditorDialogState();
}

class _AutomationEditorDialogState
    extends ConsumerState<AutomationEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _description;
  late final TextEditingController _projectId;
  late final TextEditingController _tagIds;
  late final TextEditingController _prompt;
  late final TextEditingController _cron;
  late final TextEditingController _at;
  late final TextEditingController _timezone;
  late final TextEditingController _startAt;
  late final TextEditingController _endAt;
  late final TextEditingController _maxScheduledRuns;
  late final TextEditingController _workspaceId;
  late final TextEditingController _tabId;
  late final TextEditingController _conversationId;
  late final TextEditingController _profileId;
  late final TextEditingController _sourceBranch;
  late final TextEditingController _precheck;
  late final TextEditingController _precheckTimeout;
  late final TextEditingController _queueCap;
  late final TextEditingController _inactivityTimeout;
  late final TextEditingController _heartbeatInterval;
  late final TextEditingController _misfireGrace;
  late final TextEditingController _retryMaxAttempts;
  late final TextEditingController _retryBackoff;
  late final TextEditingController _circuitThreshold;
  late final TextEditingController _circuitOpen;
  late final TextEditingController _nameTemplate;
  late String _scheduleKind;
  late String _targetKind;
  late String _setupPolicy;
  late String _overlapPolicy;
  late String _misfirePolicy;
  late String _cleanupPolicy;
  late bool _notifyOnSuccess;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final schedule =
        _nested(initial?.schedule, 'recurring') ??
        _nested(initial?.schedule, 'oneTime') ??
        const <String, Object?>{};
    final target =
        _nested(initial?.target, _firstKey(initial?.target)) ??
        const <String, Object?>{};
    _name = TextEditingController(text: initial?.name ?? 'Daily Automation');
    _slug = TextEditingController(text: initial?.slug ?? 'daily-automation');
    _description = TextEditingController(text: initial?.description ?? '');
    _projectId = TextEditingController(text: initial?.projectId ?? '');
    _tagIds = TextEditingController(text: initial?.tagIds.join(', ') ?? '');
    _prompt = TextEditingController(
      text:
          initial?.promptTemplate ??
          'Review the current workspace and report the result.',
    );
    _cron = TextEditingController(
      text: schedule['cron']?.toString() ?? '0 9 * * 1-5',
    );
    _at = TextEditingController(
      text:
          schedule['at']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
    );
    _timezone = TextEditingController(
      text: schedule['timezone']?.toString() ?? 'UTC',
    );
    _startAt = TextEditingController(
      text: schedule['startAt']?.toString() ?? '',
    );
    _endAt = TextEditingController(text: schedule['endAt']?.toString() ?? '');
    _maxScheduledRuns = TextEditingController(
      text: schedule['maxScheduledRuns']?.toString() ?? '',
    );
    _workspaceId = TextEditingController(
      text:
          target['workspaceId']?.toString() ??
          target['sourceWorkspaceId']?.toString() ??
          '',
    );
    _tabId = TextEditingController(text: target['tabId']?.toString() ?? '');
    _conversationId = TextEditingController(
      text: target['conversationId']?.toString() ?? '',
    );
    _profileId = TextEditingController(
      text: target['agentProfileId']?.toString() ?? '',
    );
    _sourceBranch = TextEditingController(
      text: target['sourceBranch']?.toString() ?? 'main',
    );
    _nameTemplate = TextEditingController(
      text:
          target['nameTemplate']?.toString() ??
          'auto-{{automation.slug}}-{{run.number}}',
    );
    final precheck = initial?.precheck;
    _precheck = TextEditingController(
      text: precheck?['command']?.toString() ?? '',
    );
    _precheckTimeout = TextEditingController(
      text: precheck?['timeoutSeconds']?.toString() ?? '120',
    );
    _queueCap = TextEditingController(text: '${initial?.queueCap ?? 10}');
    _inactivityTimeout = TextEditingController(
      text: '${initial?.inactivityTimeoutSeconds ?? 7200}',
    );
    _heartbeatInterval = TextEditingController(
      text: '${initial?.heartbeatIntervalSeconds ?? 60}',
    );
    _misfireGrace = TextEditingController(
      text: '${initial?.misfireGraceSeconds ?? 900}',
    );
    _retryMaxAttempts = TextEditingController(
      text: '${initial?.retryMaxAttempts ?? 3}',
    );
    _retryBackoff = TextEditingController(
      text: '${initial?.retryBackoffSeconds ?? 60}',
    );
    _circuitThreshold = TextEditingController(
      text: '${initial?.circuitFailureThreshold ?? 3}',
    );
    _circuitOpen = TextEditingController(
      text: '${initial?.circuitOpenSeconds ?? 900}',
    );
    _scheduleKind = initial?.schedule.containsKey('oneTime') == true
        ? 'oneTime'
        : 'recurring';
    _targetKind = initial?.target.containsKey('existingTab') == true
        ? 'existingTab'
        : initial?.target.containsKey('managedWorkspace') == true
        ? 'managedWorkspace'
        : 'freshTab';
    _setupPolicy = initial?.setupPolicy ?? 'wait';
    _overlapPolicy = initial?.overlapPolicy ?? 'skip';
    _misfirePolicy = initial?.misfirePolicy ?? 'skip';
    _cleanupPolicy = initial?.cleanupPolicy ?? 'preserve';
    _notifyOnSuccess = initial?.notifyOnSuccess ?? false;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _slug,
      _description,
      _projectId,
      _tagIds,
      _prompt,
      _cron,
      _at,
      _timezone,
      _startAt,
      _endAt,
      _maxScheduledRuns,
      _workspaceId,
      _tabId,
      _conversationId,
      _profileId,
      _sourceBranch,
      _precheck,
      _precheckTimeout,
      _queueCap,
      _inactivityTimeout,
      _heartbeatInterval,
      _misfireGrace,
      _retryMaxAttempts,
      _retryBackoff,
      _circuitThreshold,
      _circuitOpen,
      _nameTemplate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      label: 'Project (Optional)',
                      optional: true,
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
                          setState(() => _scheduleKind = value!),
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
                      ],
                      onChanged: (value) =>
                          setState(() => _targetKind = value!),
                    ),
                    const SizedBox(height: AleraTokens.space12),
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
                      _text(_conversationId, 'Agent Conversation ID'),
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
                        Expanded(
                          child: _dropdown(
                            label: 'Setup',
                            value: _setupPolicy,
                            values: const <String>['wait', 'parallel', 'skip'],
                            onChanged: (value) =>
                                setState(() => _setupPolicy = value!),
                          ),
                        ),
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
                                setState(() => _overlapPolicy = value!),
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
                                setState(() => _misfirePolicy = value!),
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space12),
                        Expanded(
                          child: _dropdown(
                            label: 'Cleanup',
                            value: _cleanupPolicy,
                            values: const <String>['preserve', 'onSuccess'],
                            onChanged: (value) =>
                                setState(() => _cleanupPolicy = value!),
                          ),
                        ),
                      ],
                    ),
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
                          setState(() => _notifyOnSuccess = value),
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

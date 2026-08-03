import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';

part 'mobile_automation_editor_helpers.dart';

Future<Map<String, Object?>?> showMobileAutomationEditor(
  BuildContext context, {
  MobileAutomation? initial,
  MobileAutomationEditorOptions? options,
}) {
  return showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MobileAutomationEditor(initial: initial, options: options),
  );
}

class _MobileAutomationEditor extends StatefulWidget {
  const _MobileAutomationEditor({this.initial, this.options});

  final MobileAutomation? initial;
  final MobileAutomationEditorOptions? options;

  @override
  State<_MobileAutomationEditor> createState() =>
      _MobileAutomationEditorState();
}

class _MobileAutomationEditorState extends State<_MobileAutomationEditor> {
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _description;
  late final TextEditingController _project;
  late final TextEditingController _tagIds;
  late final TextEditingController _prompt;
  late final TextEditingController _cron;
  late final TextEditingController _at;
  late final TextEditingController _timezone;
  late final TextEditingController _startAt;
  late final TextEditingController _endAt;
  late final TextEditingController _maxScheduledRuns;
  late final TextEditingController _workspace;
  late final TextEditingController _tab;
  late final TextEditingController _conversation;
  late final TextEditingController _profile;
  late final TextEditingController _sourceBranch;
  late final TextEditingController _nameTemplate;
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
  late String _scheduleKind;
  late String _targetKind;
  late String _setup;
  late String _overlap;
  late String _misfire;
  late String _cleanup;
  bool _notifySuccess = false;
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
    _name = TextEditingController(text: initial?.name ?? 'Automation');
    _slug = TextEditingController(text: initial?.slug ?? 'automation');
    _description = TextEditingController(text: initial?.description ?? '');
    _project = TextEditingController(text: initial?.projectId ?? '');
    _tagIds = TextEditingController(text: initial?.tagIds.join(', ') ?? '');
    _prompt = TextEditingController(
      text: initial?.promptTemplate ?? 'Review the current workspace.',
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
    _workspace = TextEditingController(
      text:
          target['workspaceId']?.toString() ??
          target['sourceWorkspaceId']?.toString() ??
          '',
    );
    _tab = TextEditingController(text: target['tabId']?.toString() ?? '');
    _conversation = TextEditingController(
      text: target['conversationId']?.toString() ?? '',
    );
    _profile = TextEditingController(
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
    _precheck = TextEditingController(
      text: _map(initial?.raw['precheck'])['command']?.toString() ?? '',
    );
    _precheckTimeout = TextEditingController(
      text:
          _map(initial?.raw['precheck'])['timeoutSeconds']?.toString() ?? '120',
    );
    _queueCap = TextEditingController(
      text: _string(initial?.raw['queueCap'], '10'),
    );
    _inactivityTimeout = TextEditingController(
      text: _string(initial?.raw['inactivityTimeoutSeconds'], '7200'),
    );
    _heartbeatInterval = TextEditingController(
      text: _string(initial?.raw['heartbeatIntervalSeconds'], '60'),
    );
    _misfireGrace = TextEditingController(
      text: _string(initial?.raw['misfireGraceSeconds'], '900'),
    );
    _retryMaxAttempts = TextEditingController(
      text: _string(initial?.raw['retryMaxAttempts'], '3'),
    );
    _retryBackoff = TextEditingController(
      text: _string(initial?.raw['retryBackoffSeconds'], '60'),
    );
    _circuitThreshold = TextEditingController(
      text: _string(initial?.raw['circuitFailureThreshold'], '3'),
    );
    _circuitOpen = TextEditingController(
      text: _string(initial?.raw['circuitOpenSeconds'], '900'),
    );
    _scheduleKind = initial?.schedule.containsKey('oneTime') == true
        ? 'oneTime'
        : 'recurring';
    _targetKind = initial?.target.containsKey('existingTab') == true
        ? 'existingTab'
        : initial?.target.containsKey('managedWorkspace') == true
        ? 'managedWorkspace'
        : 'freshTab';
    _setup = _string(initial?.raw['setupPolicy'], 'wait');
    _overlap = _string(initial?.raw['overlapPolicy'], 'skip');
    _misfire = _string(initial?.raw['misfirePolicy'], 'skip');
    _cleanup = _string(initial?.raw['cleanupPolicy'], 'preserve');
    _notifySuccess = initial?.raw['notifyOnSuccess'] == true;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _slug,
      _description,
      _project,
      _tagIds,
      _prompt,
      _cron,
      _at,
      _timezone,
      _startAt,
      _endAt,
      _maxScheduledRuns,
      _workspace,
      _tab,
      _conversation,
      _profile,
      _sourceBranch,
      _nameTemplate,
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
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _buildMobileAutomationEditor(this, context);

  void _refresh(VoidCallback callback) => setState(callback);

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(value) ? value : values.first,
        decoration: InputDecoration(labelText: label),
        items: <DropdownMenuItem<String>>[
          for (final item in values)
            DropdownMenuItem(value: item, child: Text(_title(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  void _save() {
    if (_name.text.trim().isEmpty ||
        _slug.text.trim().isEmpty ||
        _prompt.text.trim().isEmpty ||
        _workspace.text.trim().isEmpty ||
        (_targetKind == 'existingTab' &&
            (_tab.text.trim().isEmpty || _conversation.text.trim().isEmpty)) ||
        (_targetKind != 'existingTab' && _profile.text.trim().isEmpty)) {
      setState(
        () => _error = _targetKind == 'existingTab'
            ? 'The existing tab requires workspace, tab, and conversation ids.'
            : 'Name, slug, prompt, and target values are required.',
      );
      return;
    }
    final promptError = _promptTemplateError(_prompt.text);
    if (promptError != null) {
      setState(() => _error = promptError);
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final schedule = _scheduleKind == 'oneTime'
        ? <String, Object?>{
            'oneTime': <String, Object?>{
              'at': _at.text.trim(),
              'timezone': _timezone.text.trim(),
            },
          }
        : <String, Object?>{
            'recurring': <String, Object?>{
              'cron': _cron.text.trim(),
              'timezone': _timezone.text.trim(),
              if (_startAt.text.trim().isNotEmpty)
                'startAt': _startAt.text.trim(),
              if (_endAt.text.trim().isNotEmpty) 'endAt': _endAt.text.trim(),
              if (_maxScheduledRuns.text.trim().isNotEmpty)
                'maxScheduledRuns': int.tryParse(_maxScheduledRuns.text.trim()),
            },
          };
    final raw = <String, Object?>{
      ...?widget.initial?.raw,
      'id':
          widget.initial?.id ??
          'mobile-${DateTime.now().microsecondsSinceEpoch}',
      'slug': _slug.text.trim(),
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'projectId': _project.text.trim().isEmpty ? null : _project.text.trim(),
      'tagIds': _tagIds.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      'promptTemplate': _prompt.text.trim(),
      'schedule': schedule,
      'target': _target(),
      'setupPolicy': _setup,
      'cleanupPolicy': _cleanup,
      'overlapPolicy': _overlap,
      'misfirePolicy': _misfire,
      'queueCap': _intValue(_queueCap.text, 10).clamp(1, 10),
      'inactivityTimeoutSeconds': _intValue(
        _inactivityTimeout.text,
        7200,
      ).clamp(1, 86400),
      'heartbeatIntervalSeconds': _intValue(
        _heartbeatInterval.text,
        60,
      ).clamp(1, 86400),
      'misfireGraceSeconds': _intValue(_misfireGrace.text, 900).clamp(0, 86400),
      'retryMaxAttempts': _intValue(_retryMaxAttempts.text, 3).clamp(1, 3),
      'retryBackoffSeconds': _intValue(_retryBackoff.text, 60).clamp(1, 86400),
      'circuitFailureThreshold': _intValue(
        _circuitThreshold.text,
        3,
      ).clamp(1, 100),
      'circuitOpenSeconds': _intValue(_circuitOpen.text, 900).clamp(1, 86400),
      'precheck': _precheck.text.trim().isEmpty
          ? null
          : <String, Object?>{
              'command': _precheck.text.trim(),
              'timeoutSeconds': _intValue(
                _precheckTimeout.text,
                120,
              ).clamp(1, 900),
            },
      'notifyOnSuccess': _notifySuccess,
      'state': widget.initial?.state ?? 'draft',
      'revision': widget.initial?.revision ?? 0,
      'approvedRevision': widget.initial?.approvedRevision,
      'createdBy':
          widget.initial?.raw['createdBy'] ??
          <String, Object?>{'kind': 'authenticatedMobile'},
      'modifiedBy':
          widget.initial?.raw['modifiedBy'] ??
          <String, Object?>{'kind': 'authenticatedMobile'},
      'createdAt': widget.initial?.raw['createdAt'] ?? now,
      'updatedAt': now,
    };
    Navigator.of(context).pop(raw);
  }

  Map<String, Object?> _target() {
    final existing = _nested(widget.initial?.target, 'existingTab');
    return switch (_targetKind) {
      'existingTab' => <String, Object?>{
        'existingTab': <String, Object?>{
          ...?existing,
          'workspaceId': _workspace.text.trim(),
          'tabId': _tab.text.trim(),
          'conversationId': _conversation.text.trim(),
        },
      },
      'managedWorkspace' => <String, Object?>{
        'managedWorkspace': <String, Object?>{
          'sourceWorkspaceId': _workspace.text.trim(),
          'sourceBranch': _sourceBranch.text.trim(),
          'nameTemplate': _nameTemplate.text.trim(),
          'agentProfileId': _profile.text.trim(),
        },
      },
      _ => <String, Object?>{
        'freshTab': <String, Object?>{
          'workspaceId': _workspace.text.trim(),
          'agentProfileId': _profile.text.trim(),
        },
      },
    };
  }

  String _title(String value) => value == 'onSuccess'
      ? 'On Success'
      : value == 'runLatestOnce'
      ? 'Run Latest Once'
      : value == 'forceParallel'
      ? 'Force Parallel'
      : '${value[0].toUpperCase()}${value.substring(1)}';

  int _intValue(String value, int fallback) =>
      int.tryParse(value.trim()) ?? fallback;
}

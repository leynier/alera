part of 'automation_editor_dialog.dart';

JsonMap? _nested(JsonMap? map, String? key) {
  final value = key == null ? null : map?[key];
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

String? _firstKey(JsonMap? map) =>
    map == null || map.isEmpty ? null : map.keys.first;

extension on _AutomationEditorDialogState {
  Widget _text(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return AleraTextField(
      controller: controller,
      labelText: label,
      minLines: maxLines == 1 ? null : maxLines,
      maxLines: maxLines,
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        for (final option in values)
          DropdownMenuItem<String>(value: option, child: Text(_title(option))),
      ],
      onChanged: onChanged,
    );
  }

  Widget _idPicker({
    required TextEditingController controller,
    required String label,
    required List<({String id, String label})> options,
    bool optional = false,
  }) {
    final current = controller.text.trim();
    final labels = <String, String>{
      if (optional) '': 'None',
      for (final option in options) option.id: option.label,
    };
    if (!labels.containsKey(current)) {
      labels[current] = current.isEmpty ? 'Select...' : current;
    }
    final value = labels.containsKey(current) ? current : '';
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        for (final entry in labels.entries)
          DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (next) {
        if (next == null) {
          return;
        }
        // ignore: invalid_use_of_protected_member
        setState(() => controller.text = next);
      },
    );
  }

  void _save() {
    final name = _name.text.trim();
    final slug = _slug.text.trim();
    if (name.isEmpty || slug.isEmpty || _prompt.text.trim().isEmpty) {
      // ignore: invalid_use_of_protected_member
      setState(() => _error = 'Name, slug, and prompt template are required.');
      return;
    }
    final promptError = _promptTemplateError(_prompt.text);
    if (promptError != null) {
      // ignore: invalid_use_of_protected_member
      setState(() => _error = promptError);
      return;
    }
    if (_workspaceId.text.trim().isEmpty ||
        (_targetKind == 'existingTab' &&
            (_tabId.text.trim().isEmpty ||
                _conversationId.text.trim().isEmpty)) ||
        (_targetKind != 'existingTab' && _profileId.text.trim().isEmpty)) {
      // ignore: invalid_use_of_protected_member
      setState(
        () => _error = _targetKind == 'existingTab'
            ? 'The existing tab requires workspace, tab, and conversation ids.'
            : 'The selected target requires its ids.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final target = switch (_targetKind) {
      'existingTab' => <String, Object?>{
        'existingTab': <String, Object?>{
          'workspaceId': _workspaceId.text.trim(),
          'tabId': _tabId.text.trim(),
          'conversationId': _conversationId.text.trim(),
        },
      },
      'managedWorkspace' => <String, Object?>{
        'managedWorkspace': <String, Object?>{
          'sourceWorkspaceId': _workspaceId.text.trim(),
          'sourceBranch': _sourceBranch.text.trim(),
          'nameTemplate': _nameTemplate.text.trim(),
          'agentProfileId': _profileId.text.trim(),
        },
      },
      _ => <String, Object?>{
        'freshTab': <String, Object?>{
          'workspaceId': _workspaceId.text.trim(),
          'agentProfileId': _profileId.text.trim(),
        },
      },
    };
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
                'maxScheduledRuns': _intValue(_maxScheduledRuns.text, 1),
            },
          };
    final raw = <String, Object?>{
      ...widget.initial?.raw ?? const <String, Object?>{},
      'id': widget.initial?.id ?? const Uuid().v4(),
      'slug': slug,
      'name': name,
      'description': _description.text.trim(),
      'projectId': _projectId.text.trim().isEmpty
          ? null
          : _projectId.text.trim(),
      'tagIds': _tagIds.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      'promptTemplate': _prompt.text.trim(),
      'schedule': schedule,
      'target': target,
      'setupPolicy': _setupPolicy,
      'cleanupPolicy': _cleanupPolicy,
      'overlapPolicy': _overlapPolicy,
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
      'misfirePolicy': _misfirePolicy,
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
              ).clamp(1, 3600),
            },
      'notifyOnSuccess': _notifyOnSuccess,
      'state': widget.initial?.state ?? 'draft',
      'revision': widget.initial?.revision ?? 0,
      'approvedRevision': widget.initial?.approvedRevision,
      'createdBy':
          widget.initial?.raw['createdBy'] ??
          <String, Object?>{'kind': 'humanDesktop'},
      'modifiedBy':
          widget.initial?.raw['modifiedBy'] ??
          <String, Object?>{'kind': 'humanDesktop'},
      'createdAt': widget.initial?.raw['createdAt'] ?? now,
      'updatedAt': now,
    };
    Navigator.of(context).pop(<String, Object?>{...raw});
  }

  String _title(String value) => switch (value) {
    'oneTime' => 'One-time',
    'runLatestOnce' => 'Run Latest Once',
    'existingTab' => 'Existing Tab',
    'freshTab' => 'Fresh Tab',
    'managedWorkspace' => 'Managed Workspace',
    _ => '${value[0].toUpperCase()}${value.substring(1)}',
  };

  int _intValue(String value, int fallback) =>
      int.tryParse(value.trim()) ?? fallback;
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

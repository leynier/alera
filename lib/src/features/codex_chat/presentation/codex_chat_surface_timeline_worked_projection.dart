part of 'codex_chat_surface.dart';

_CodexWorkedAction _codexWorkedAction(CodexTimelineCell cell) {
  final cached = _codexWorkedActionCache[cell];
  if (cached != null) return cached;
  final action = _createCodexWorkedAction(cell);
  _codexWorkedActionCache[cell] = action;
  return action;
}

_CodexWorkedAction _createCodexWorkedAction(CodexTimelineCell cell) {
  if (cell.kind == CodexTimelineKind.diff) {
    final changes = _codexChanges(cell.metadata['changes']);
    final changeCount = _codexChangeCount(cell, changes);
    return _CodexWorkedAction(
      cell: cell,
      kind: .edit,
      label: _codexEditLabel(cell, changes, changeCount: changeCount),
      hasDetails: _codexWorkedActionHasDetails(cell),
      itemCount: math.max(1, changeCount),
    );
  }
  final itemType = cell.metadata['itemType']?.toString().toLowerCase();
  if (itemType == 'enteredreviewmode' || itemType == 'exitedreviewmode') {
    return _CodexWorkedAction(
      cell: cell,
      kind: .review,
      label: itemType == 'enteredreviewmode'
          ? 'Entered review mode'
          : 'Exited review mode',
      hasDetails: _codexWorkedActionHasDetails(cell),
    );
  }
  if (itemType == 'websearch') {
    final query = cell.metadata['query']?.toString().trim() ?? '';
    return _CodexWorkedAction(
      cell: cell,
      kind: .webSearch,
      label: query.isEmpty ? 'Searched the web' : 'Searched the web for $query',
      hasDetails: _codexWorkedActionHasDetails(cell),
    );
  }
  if (itemType == 'imageview') {
    final path = <Object?>[cell.subtitle, cell.metadata['path']]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return _CodexWorkedAction(
      cell: cell,
      kind: .viewImage,
      label: path.isEmpty ? 'Viewed image' : 'Viewed image · $path',
      hasDetails: _codexWorkedActionHasDetails(cell),
    );
  }
  if (itemType == 'mcptoolcall' || itemType == 'dynamictoolcall') {
    final tool = _firstWorkedValue(<Object?>[
      cell.metadata['tool'],
      cell.title,
    ]);
    return _CodexWorkedAction(
      cell: cell,
      kind: .tool,
      label: 'Used $tool',
      hasDetails: _codexWorkedActionHasDetails(cell),
    );
  }
  final actions = _codexCommandActions(cell.metadata['commandActions']);
  final selected = _primaryCodexCommandAction(actions);
  final kind = switch (selected?['type']?.toString().toLowerCase()) {
    'search' => _CodexWorkedActionKind.search,
    'read' => _CodexWorkedActionKind.read,
    'listfiles' || 'list_files' => _CodexWorkedActionKind.listFiles,
    _ => _CodexWorkedActionKind.ran,
  };
  return _CodexWorkedAction(
    cell: cell,
    kind: kind,
    label: _codexCommandActionLabel(cell, selected, kind),
    hasDetails: _codexWorkedActionHasDetails(cell),
  );
}

List<Map<String, Object?>> _codexCommandActions(Object? raw) {
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } catch (_) {
      value = null;
    }
  }
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final action in value)
      if (action is Map)
        <String, Object?>{
          for (final entry in action.entries) entry.key.toString(): entry.value,
        },
  ];
}

Map<String, Object?>? _primaryCodexCommandAction(
  List<Map<String, Object?>> actions,
) {
  for (final type in const <String>[
    'search',
    'read',
    'listfiles',
    'list_files',
  ]) {
    for (final action in actions) {
      if (action['type']?.toString().toLowerCase() == type) return action;
    }
  }
  return actions.firstOrNull;
}

String _codexCommandActionLabel(
  CodexTimelineCell cell,
  Map<String, Object?>? action,
  _CodexWorkedActionKind kind,
) {
  final command = _firstWorkedValue(<Object?>[
    action?['command'],
    cell.subtitle,
    cell.title,
  ]);
  return switch (kind) {
    _CodexWorkedActionKind.review => cell.title ?? 'Review mode changed',
    _CodexWorkedActionKind.read =>
      'Read ${_codexActionTarget(action, fallback: command)}',
    _CodexWorkedActionKind.listFiles =>
      action?['path'] == null
          ? 'Listed files'
          : 'Listed files in ${_codexActionTarget(action, fallback: command)}',
    _CodexWorkedActionKind.search =>
      action?['query'] == null
          ? 'Searched with $command'
          : 'Searched for ${action!['query']}',
    _CodexWorkedActionKind.webSearch => 'Searched the web',
    _CodexWorkedActionKind.tool => 'Used $command',
    _CodexWorkedActionKind.ran => 'Ran $command',
    _CodexWorkedActionKind.edit => _codexEditLabel(
      cell,
      _codexChanges(cell.metadata['changes']),
      changeCount: _codexChangeCount(
        cell,
        _codexChanges(cell.metadata['changes']),
      ),
    ),
    _CodexWorkedActionKind.viewImage => 'Viewed image',
  };
}

String _codexActionTarget(
  Map<String, Object?>? action, {
  required String fallback,
}) {
  final target = _firstWorkedValue(<Object?>[
    action?['name'],
    action?['path'],
    fallback,
  ]);
  return p.basename(target);
}

String _codexEditLabel(
  CodexTimelineCell cell,
  List<Map<String, Object?>> changes, {
  required int changeCount,
}) {
  if (changeCount != 1) {
    return changeCount == 0 ? 'Edited files' : 'Edited $changeCount files';
  }
  final change = changes.single;
  final path = change['path']?.toString().trim() ?? '';
  final counts = _codexDiffCounts(change['diff']?.toString() ?? '');
  final suffix = counts.$1 == 0 && counts.$2 == 0
      ? ''
      : ' +${counts.$1} -${counts.$2}';
  return 'Edited ${path.isEmpty ? 'file' : p.basename(path)}$suffix';
}

List<Map<String, Object?>> _codexChanges(Object? raw) {
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } catch (_) {
      value = null;
    }
  }
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final change in value)
      if (change is Map && change['truncated'] != true)
        <String, Object?>{
          for (final entry in change.entries) entry.key.toString(): entry.value,
        },
  ];
}

int _codexChangeCount(
  CodexTimelineCell cell,
  List<Map<String, Object?>> visibleChanges,
) {
  final count = cell.metadata['changesCount'];
  if (count is num && count.isFinite && count >= 0) return count.toInt();
  return visibleChanges.length;
}

(int, int) _codexDiffCounts(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) additions += 1;
    if (line.startsWith('-') && !line.startsWith('---')) deletions += 1;
  }
  return (additions, deletions);
}

String _codexWorkedSummary(List<_CodexWorkedAction> actions) {
  final counts = <_CodexWorkedActionKind, int>{};
  for (final action in actions) {
    counts.update(
      action.kind,
      (count) => count + action.itemCount,
      ifAbsent: () => action.itemCount,
    );
  }
  final labels = <String>[];
  for (final kind in _CodexWorkedActionKind.values) {
    final count = counts[kind];
    if (count == null) continue;
    labels.add(switch (kind) {
      _CodexWorkedActionKind.review =>
        count == 1
            ? actions
                  .firstWhere(
                    (action) => action.kind == _CodexWorkedActionKind.review,
                  )
                  .label
                  .toLowerCase()
            : 'changed review mode $count times',
      _CodexWorkedActionKind.edit =>
        'edited $count ${count == 1 ? 'file' : 'files'}',
      _CodexWorkedActionKind.read =>
        'read $count ${count == 1 ? 'file' : 'files'}',
      _CodexWorkedActionKind.viewImage =>
        'viewed $count ${count == 1 ? 'image' : 'images'}',
      _CodexWorkedActionKind.listFiles =>
        'listed $count ${count == 1 ? 'file' : 'files'}',
      _CodexWorkedActionKind.search =>
        'searched $count ${count == 1 ? 'file' : 'files'}',
      _CodexWorkedActionKind.webSearch =>
        'searched the web $count ${count == 1 ? 'time' : 'times'}',
      _CodexWorkedActionKind.tool =>
        'used $count ${count == 1 ? 'tool' : 'tools'}',
      _CodexWorkedActionKind.ran =>
        'ran $count ${count == 1 ? 'command' : 'commands'}',
    });
  }
  final summary = labels.join(', ');
  return '${summary[0].toUpperCase()}${summary.substring(1)}';
}

IconData _codexWorkedSummaryIcon(List<_CodexWorkedAction> actions) {
  if (actions.any((action) => action.kind == _CodexWorkedActionKind.edit)) {
    return AleraIcons.edit;
  }
  return actions.first.icon;
}

bool _codexWorkedActionHasDetails(CodexTimelineCell cell) =>
    (cell.detailsText ?? cell.markdownText ?? '').trim().isNotEmpty ||
    <Object?>[
      cell.metadata['query'],
      cell.metadata['changes'],
      cell.metadata['arguments'],
      cell.metadata['commandActions'],
      cell.metadata['result'],
      cell.metadata['error'],
      cell.metadata['contentItems'],
      cell.metadata['results'],
      cell.metadata['aggregatedOutput'],
      cell.metadata['output'],
      cell.metadata['diff'],
      cell.metadata['commandOutput'],
    ].any((value) => value != null);

String _firstWorkedValue(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return 'tool';
}

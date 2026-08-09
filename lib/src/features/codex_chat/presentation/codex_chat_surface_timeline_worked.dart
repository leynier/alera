part of 'codex_chat_surface.dart';

enum _CodexWorkedActionKind {
  edit,
  read,
  viewImage,
  listFiles,
  search,
  webSearch,
  ran,
}

class _CodexWorkedAction {
  const _CodexWorkedAction({
    required this.cell,
    required this.kind,
    required this.label,
    required this.hasDetails,
    this.itemCount = 1,
  });

  final CodexTimelineCell cell;
  final _CodexWorkedActionKind kind;
  final String label;
  final bool hasDetails;
  final int itemCount;

  IconData get icon => switch (kind) {
    _CodexWorkedActionKind.edit => AleraIcons.edit,
    _CodexWorkedActionKind.read => AleraIcons.read,
    _CodexWorkedActionKind.viewImage => AleraIcons.viewImage,
    _CodexWorkedActionKind.listFiles => AleraIcons.file,
    _CodexWorkedActionKind.search => AleraIcons.search,
    _CodexWorkedActionKind.webSearch => AleraIcons.search,
    _CodexWorkedActionKind.ran => AleraIcons.terminal,
  };
}

final Expando<_CodexWorkedAction> _codexWorkedActionCache =
    Expando<_CodexWorkedAction>('codex worked action');

class _CodexWorkedActionGroup extends StatelessWidget {
  const _CodexWorkedActionGroup({
    required this.projection,
    required this.expanded,
    required this.expandedActions,
    required this.onToggle,
    required this.onToggleAction,
  });

  final _CodexSecondaryRowProjection projection;
  final bool expanded;
  final Set<String> expandedActions;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleAction;

  @override
  Widget build(BuildContext context) {
    final projection = this.projection;
    final actions = projection.actions;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            key: ValueKey<String>(
              'worked-action-group-${actions.first.cell.id}',
            ),
            onTap: onToggle,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    projection.summaryIcon!,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Flexible(
                    child: projection.streaming
                        ? _CodexShimmerText(
                            key: const ValueKey<String>(
                              'codex-streaming-worked-summary',
                            ),
                            text: projection.summary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          )
                        : Text(
                            projection.summary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          ),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final action in actions)
                    _CodexWorkedActionRow(
                      key: ValueKey<String>(
                        'codex-worked-row-${action.cell.id}',
                      ),
                      action: action,
                      expanded: expandedActions.contains(action.cell.id),
                      onToggle: () => onToggleAction(action.cell.id),
                    ),
                  if (projection.waiting) const _CodexWorkedWaitingRow(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CodexWorkedWaitingRow extends StatelessWidget {
  const _CodexWorkedWaitingRow();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('codex-synthetic-worked-waiting'),
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space6,
      vertical: AleraTokens.space4,
    ),
    child: Row(
      children: <Widget>[
        const Icon(
          AleraIcons.ai,
          size: AleraTokens.iconMd,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space8),
        _CodexShimmerText(
          text: 'Working',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ],
    ),
  );
}

class _CodexWorkedActionRow extends StatelessWidget {
  const _CodexWorkedActionRow({
    super.key,
    required this.action,
    required this.expanded,
    required this.onToggle,
  });

  final _CodexWorkedAction action;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final hasDetails = action.hasDetails;
    final color = action.cell.status == CodexTimelineStatus.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          key: ValueKey<String>('worked-action-${action.cell.id}'),
          onTap: hasDetails ? onToggle : null,
          mouseCursor: hasDetails
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Icon(action.icon, size: AleraTokens.iconMd, color: color),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: action.cell.isStreaming
                      ? _CodexShimmerText(
                          text: action.label,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: color),
                        )
                      : Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: color),
                        ),
                ),
                if (!action.cell.isStreaming && hasDetails)
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
              ],
            ),
          ),
        ),
        if (expanded && hasDetails)
          Container(
            margin: const EdgeInsets.only(
              left: AleraTokens.space24,
              top: AleraTokens.space4,
              bottom: AleraTokens.space4,
            ),
            padding: const EdgeInsets.all(AleraTokens.space8),
            decoration: BoxDecoration(
              color: AleraTokens.surface,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              border: Border.all(color: AleraTokens.borderSubtle),
            ),
            child: _CodexToolDetails(cell: action.cell),
          ),
      ],
    );
  }
}

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
    return _CodexWorkedAction(
      cell: cell,
      kind: _CodexWorkedActionKind.edit,
      label: _codexEditLabel(cell, changes),
      hasDetails: _codexWorkedActionHasDetails(cell),
      itemCount: math.max(1, changes.length),
    );
  }
  final itemType = cell.metadata['itemType']?.toString().toLowerCase();
  if (itemType == 'websearch') {
    final query = cell.metadata['query']?.toString().trim() ?? '';
    return _CodexWorkedAction(
      cell: cell,
      kind: _CodexWorkedActionKind.webSearch,
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
      kind: _CodexWorkedActionKind.viewImage,
      label: path.isEmpty ? 'Viewed image' : 'Viewed image · $path',
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
    _CodexWorkedActionKind.ran => 'Ran $command',
    _CodexWorkedActionKind.edit => _codexEditLabel(
      cell,
      _codexChanges(cell.metadata['changes']),
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
  List<Map<String, Object?>> changes,
) {
  if (changes.length != 1) {
    return changes.isEmpty ? 'Edited files' : 'Edited ${changes.length} files';
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
      if (change is Map)
        <String, Object?>{
          for (final entry in change.entries) entry.key.toString(): entry.value,
        },
  ];
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
    ].any((value) => value != null);

String _firstWorkedValue(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return 'command';
}

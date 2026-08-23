part of 'codex_timeline.dart';

List<CodexTimelineCell>? _reduceTurnLifecycle(_CodexTimelineEvent event) {
  if (event.method == 'turn/started' || event.method == 'turn/created') {
    if (event.turnId.isEmpty) return event.cells;
    final turn = _map(event.params['turn']);
    return _upsert(
      event.cells,
      _newCell(
        id: 'turn-${event.turnId}',
        turnId: event.turnId,
        kind: CodexTimelineKind.turnSeparator,
        status: CodexTimelineStatus.info,
        timestamp: event.timestamp,
        title: 'Turn started',
        metadata: <String, Object?>{
          'startedAt': turn['startedAt'],
          'completedAt': turn['completedAt'],
          'computedDurationMs': turn['durationMs'],
        },
      ),
    );
  }

  if (event.method != 'turn/completed' &&
      event.method != 'turn/failed' &&
      event.method != 'turn/aborted' &&
      event.method != 'turn/interrupted') {
    return null;
  }
  final turnError = _map(event.params['turn'])['error'];
  final failed =
      event.method == 'turn/failed' ||
      (turnError is String && turnError.trim().isNotEmpty) ||
      (turnError is Map && turnError.isNotEmpty);
  final completed = <CodexTimelineCell>[
    for (final cell in event.cells)
      if (event.turnId.isNotEmpty &&
          cell.turnId == event.turnId &&
          cell.isStreaming)
        cell.copyWith(
          status: failed
              ? CodexTimelineStatus.failed
              : CodexTimelineStatus.completed,
          isStreaming: false,
          updatedAt: event.timestamp,
        )
      else
        cell,
  ];
  return _updateTurnSeparator(
    completed,
    event.turnId,
    event.params,
    event.timestamp,
  );
}

List<CodexTimelineCell>? _reduceItemLifecycle(_CodexTimelineEvent event) {
  if (event.method != 'item/started' &&
      event.method != 'item/completed' &&
      event.method != 'item/updated') {
    return null;
  }
  if (event.turnId.isEmpty) return event.cells;
  final provisionalId = event.itemId.isEmpty
      ? '${event.type}-${event.turnId}'
      : 'item-${event.itemId}';
  final existing = _find(event.cells, provisionalId);
  final phase = _firstString(<Object?>[
    event.item['phase'],
    event.params['phase'],
    existing?.metadata['streamPhase'],
  ]);
  final isAgentMessage =
      event.type.contains('agentmessage') || event.type.contains('assistant');
  final kind = isAgentMessage && phase == 'commentary'
      ? CodexTimelineKind.progressText
      : _kindFor(event.type, event.lowerMethod);
  final id = kind == CodexTimelineKind.userMessage
      ? 'user-${event.turnId}'
      : event.itemId.isEmpty
      ? '${kind.name}-${event.turnId}'
      : 'item-${event.itemId}';
  final current = _find(event.cells, id) ?? existing;
  final fullText = _itemMarkdown(event.item);
  final details = _itemDetails(event.item);
  final rawStatus = (event.item['status'] ?? event.params['status'] ?? '')
      .toString()
      .toLowerCase();
  final status = rawStatus.contains('fail')
      ? CodexTimelineStatus.failed
      : rawStatus.contains('declin')
      ? CodexTimelineStatus.declined
      : event.method == 'item/completed'
      ? CodexTimelineStatus.completed
      : CodexTimelineStatus.inProgress;
  return _upsert(
    event.cells,
    _newCell(
      id: id,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: kind,
      status: status,
      timestamp: event.timestamp,
      title: event.type.contains('contextcompaction')
          ? _contextCompactionTitle(status)
          : _titleFor(event.type, event.lowerMethod, item: event.item),
      subtitle: _firstString(<Object?>[
        event.item['command'],
        event.item['name'],
        event.item['path'],
        event.item['cwd'],
        event.item['server'],
      ]),
      markdownText: fullText.isEmpty ? current?.markdownText : fullText,
      detailsText: details.isEmpty ? current?.detailsText : details,
      isStreaming: event.method != 'item/completed',
      metadata: <String, Object?>{
        ...?current?.metadata,
        ..._itemTimelineMetadata(event.item),
        if (isAgentMessage && phase.isNotEmpty) 'streamPhase': phase,
      },
    ),
  );
}

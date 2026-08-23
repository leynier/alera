part of 'mobile_codex_state.dart';

/// Rebuilds a stable mobile timeline when an older host only persisted raw
/// app-server events and has no timeline projection yet.
abstract final class MobileCodexTimelineReducer {
  static List<MobileCodexTimelineCell> reduce(
    List<MobileCodexTimelineCell> cells,
    Map<String, Object?> message,
  ) {
    final event = _MobileCodexTimelineEvent.fromMessage(message);
    return _reduceTurnEvent(cells, event) ??
        _reduceStreamEvent(cells, event) ??
        _reduceItemEvent(cells, event) ??
        _reduceNoticeEvent(cells, event) ??
        cells;
  }

  static List<MobileCodexTimelineCell>? _reduceTurnEvent(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    if (event.rawMethod == 'codex/event/task_complete') {
      return _completeLegacyTask(cells, event);
    }
    return switch (event.method) {
      'thread/compacted' => _reduceLegacyMobileContextCompaction(
        cells,
        event.turnId,
      ),
      'turn/started' || 'turn/created' => _startTurn(cells, event.turnId),
      'turn/completed' ||
      'turn/aborted' ||
      'turn/interrupted' => _close(cells, event.turnId, 'completed'),
      'turn/failed' => _close(cells, event.turnId, 'failed'),
      'turn/diff/updated' => _replaceDiffSnapshot(cells, event),
      _ => null,
    };
  }

  static List<MobileCodexTimelineCell> _completeLegacyTask(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final text = _first(<Object?>[
      event.legacy['last_agent_message'],
      event.legacy['lastAgentMessage'],
    ]);
    var next = cells;
    if (text.isNotEmpty && event.turnId.isNotEmpty) {
      next = _upsert(
        next,
        _cell(
          id: 'assistant-${event.turnId}',
          turnId: event.turnId,
          kind: 'assistantMessage',
          status: 'completed',
          title: 'Codex',
          markdownText: text,
        ),
      );
    }
    return _close(next, event.turnId, 'completed');
  }

  static List<MobileCodexTimelineCell> _startTurn(
    List<MobileCodexTimelineCell> cells,
    String turnId,
  ) {
    if (turnId.isEmpty) return cells;
    return _upsert(
      cells,
      _cell(
        id: 'turn-$turnId',
        turnId: turnId,
        kind: 'turnSeparator',
        status: 'info',
        title: 'Turn started',
      ),
    );
  }

  static List<MobileCodexTimelineCell> _replaceDiffSnapshot(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final delta = _first(<Object?>[
      event.params['diff'],
      event.params['delta'],
      event.params['text'],
    ]);
    final hasSnapshot =
        event.params.containsKey('diff') ||
        event.params.containsKey('delta') ||
        event.params.containsKey('text');
    if (event.turnId.isEmpty || !hasSnapshot) return cells;
    final id = 'diff-${event.turnId}';
    final existing = _find(cells, id);
    if (existing?.metadata['lastDelta'] == delta) return cells;
    return _upsert(
      cells,
      _cell(
        id: id,
        turnId: event.turnId,
        kind: 'diff',
        status: 'inProgress',
        title: 'File changes',
        detailsText: delta,
        isStreaming: true,
        metadata: <String, Object?>{...?existing?.metadata, 'lastDelta': delta},
      ),
    );
  }

  static List<MobileCodexTimelineCell>? _reduceStreamEvent(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final source = _sourceFor(event.lowerMethod);
    if (source != null) {
      return _appendDelta(cells, event, source);
    }
    final isSubAgent =
        event.lowerMethod.contains('subagent') ||
        event.lowerMethod.contains('collab');
    if (!isSubAgent || event.turnId.isEmpty) return null;
    return _reduceSubAgentEvent(cells, event);
  }

  static List<MobileCodexTimelineCell> _reduceSubAgentEvent(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final delta = _first(<Object?>[
      event.params['delta'],
      event.params['text'],
      event.params['summary'],
      event.params['message'],
      event.legacy['summary'],
      event.legacy['message'],
    ]);
    final id = event.itemId.isEmpty
        ? 'subAgent-${event.turnId}'
        : 'item-${event.itemId}';
    final existing = _find(cells, id);
    if (existing?.metadata['lastDelta'] == delta) return cells;
    final isCompleted =
        event.lowerMethod.contains('completed') ||
        event.lowerMethod.contains('end');
    return _upsert(
      cells,
      _cell(
        id: id,
        itemId: event.itemId.isEmpty ? null : event.itemId,
        turnId: event.turnId,
        kind: 'subAgent',
        status: isCompleted ? 'completed' : 'inProgress',
        title: 'Sub-agent',
        markdownText: delta.isEmpty
            ? existing?.markdownText
            : '${existing?.markdownText ?? ''}$delta',
        isStreaming: !isCompleted,
        metadata: <String, Object?>{
          ...?existing?.metadata,
          if (delta.isNotEmpty) 'lastDelta': delta,
        },
      ),
    );
  }

  static List<MobileCodexTimelineCell>? _reduceItemEvent(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) => switch (event.method) {
    'item/started' ||
    'item/completed' ||
    'item/updated' => _upsertItem(cells, event),
    _ => null,
  };

  static List<MobileCodexTimelineCell> _upsertItem(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    if (event.turnId.isEmpty) return cells;
    final baseKind = _kindFor(event.itemType, event.lowerMethod);
    final provisionalId = event.itemId.isEmpty
        ? '$baseKind-${event.turnId}'
        : 'item-${event.itemId}';
    final existing = _find(cells, provisionalId);
    final phase = _first(<Object?>[
      event.item['phase'],
      event.params['phase'],
      existing?.metadata['streamPhase'],
    ]);
    final isAgent =
        event.itemType.contains('agentmessage') ||
        event.itemType.contains('assistant');
    final kind = isAgent && phase == 'commentary' ? 'progressText' : baseKind;
    final id = event.itemId.isEmpty
        ? '$kind-${event.turnId}'
        : 'item-${event.itemId}';
    final current = _find(cells, id) ?? existing;
    final statusRaw = _first(<Object?>[
      event.item['status'],
      event.params['status'],
    ]).toLowerCase();
    final status = statusRaw.contains('fail')
        ? 'failed'
        : statusRaw.contains('declin')
        ? 'declined'
        : event.method == 'item/completed'
        ? 'completed'
        : 'inProgress';
    final details = _mobileCodexItemDetails(event.item);
    return _upsert(
      cells,
      _cell(
        id: id,
        itemId: event.itemId.isEmpty ? null : event.itemId,
        turnId: event.turnId,
        kind: kind,
        status: status,
        title: event.itemType.contains('contextcompaction')
            ? mobileCodexContextCompactionTitle(status)
            : _titleFor(event.itemType, event.lowerMethod, event.item),
        subtitle: _first(<Object?>[
          event.item['command'],
          event.item['name'],
          event.item['path'],
        ]),
        markdownText: _first(<Object?>[
          event.item['text'],
          event.item['content'],
          event.item['summary'],
          event.item['message'],
        ]),
        detailsText: details.isEmpty ? null : details,
        isStreaming: event.method != 'item/completed',
        metadata: <String, Object?>{
          ...?current?.metadata,
          ..._mobileCodexItemMetadata(event.item),
          if (isAgent && phase.isNotEmpty) 'streamPhase': phase,
        },
      ),
    );
  }

  static List<MobileCodexTimelineCell>? _reduceNoticeEvent(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) => switch (event.method) {
    'error' || 'stream/error' || 'stream_error' => _appendError(cells, event),
    _ when event.lowerMethod.contains('review') && event.turnId.isNotEmpty =>
      _upsertReview(cells, event),
    _ => null,
  };

  static List<MobileCodexTimelineCell> _appendError(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final text = _first(<Object?>[
      event.params['message'],
      event.params['error'],
      event.message['error'],
    ]);
    if (text.isEmpty) return cells;
    return <MobileCodexTimelineCell>[
      ...cells,
      _cell(
        id: 'error-${DateTime.now().microsecondsSinceEpoch}',
        turnId: event.turnId.isEmpty ? null : event.turnId,
        kind: 'systemNotice',
        status: 'failed',
        title: 'Codex error',
        markdownText: text,
      ),
    ];
  }

  static List<MobileCodexTimelineCell> _upsertReview(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
  ) {
    final review = _first(<Object?>[
      event.params['review'],
      event.params['text'],
    ]);
    final isEntering = event.lowerMethod.contains('enter');
    return _upsert(
      cells,
      _cell(
        id: event.itemId.isEmpty
            ? 'review-${event.turnId}'
            : 'item-${event.itemId}',
        itemId: event.itemId.isEmpty ? null : event.itemId,
        turnId: event.turnId,
        kind: 'toolCall',
        status: 'completed',
        title: isEntering ? 'Entered review mode' : 'Exited review mode',
        detailsText: review.isEmpty ? null : review,
        metadata: <String, Object?>{
          'itemType': isEntering ? 'enteredReviewMode' : 'exitedReviewMode',
        },
      ),
    );
  }

  static List<MobileCodexTimelineCell> _appendDelta(
    List<MobileCodexTimelineCell> cells,
    _MobileCodexTimelineEvent event,
    String source,
  ) {
    if (event.turnId.isEmpty) return cells;
    final values = <Object?>[
      event.params['delta'],
      event.params['text'],
      event.legacy['delta'],
      event.legacy['text'],
    ];
    if (source == 'output') {
      values.addAll(<Object?>[
        event.params['output'],
        event.params['interaction'],
      ]);
    } else if (source == 'agent') {
      values.add(event.legacy['message']);
    }
    final delta = _rawFirst(values);
    if (delta.isEmpty) return cells;
    final itemType = event.item['type']?.toString().toLowerCase() ?? '';
    final provisional = event.itemId.isEmpty
        ? '${_kindFor(itemType, source)}-${event.turnId}'
        : 'item-${event.itemId}';
    final existing = _find(cells, provisional);
    final phase = _first(<Object?>[
      event.item['phase'],
      event.params['phase'],
      existing?.metadata['streamPhase'],
    ]);
    final kind = source == 'agent'
        ? phase.isEmpty || phase == 'final_answer' || phase == 'final'
              ? 'assistantMessage'
              : 'progressText'
        : source == 'reasoning'
        ? 'reasoning'
        : _kindFor(itemType, source);
    final id = event.itemId.isEmpty
        ? '$kind-${event.turnId}'
        : 'item-${event.itemId}';
    final current = _find(cells, id);
    if (current?.metadata['lastDelta'] == delta) return cells;
    return _upsert(
      cells,
      _cell(
        id: id,
        itemId: event.itemId.isEmpty ? null : event.itemId,
        turnId: event.turnId,
        kind: kind,
        status: 'inProgress',
        title: source == 'reasoning'
            ? 'Reasoning'
            : source == 'output'
            ? _titleFor(itemType, source, event.item)
            : 'Codex',
        markdownText: source == 'output'
            ? null
            : '${current?.markdownText ?? ''}$delta',
        detailsText: source == 'output'
            ? '${current?.detailsText ?? ''}$delta'
            : null,
        isStreaming: true,
        metadata: <String, Object?>{
          ...?current?.metadata,
          'lastDelta': delta,
          if (source == 'agent')
            'streamPhase': kind == 'assistantMessage'
                ? 'final_answer'
                : 'commentary',
        },
      ),
    );
  }

  static List<MobileCodexTimelineCell> _close(
    List<MobileCodexTimelineCell> cells,
    String turnId,
    String status,
  ) => <MobileCodexTimelineCell>[
    for (final cell in cells)
      turnId.isNotEmpty && cell.turnId == turnId && cell.isStreaming
          ? cell.copyWith(status: status, isStreaming: false)
          : cell,
  ];

  static MobileCodexTimelineCell _cell({
    required String id,
    required String kind,
    required String status,
    String? turnId,
    String? itemId,
    String? title,
    String? subtitle,
    String? markdownText,
    String? detailsText,
    bool isStreaming = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => MobileCodexTimelineCell(
    id: id,
    kind: kind,
    status: status,
    turnId: turnId,
    itemId: itemId,
    title: title,
    subtitle: subtitle,
    markdownText: markdownText,
    renderedMarkdownText: markdownText,
    detailsText: detailsText,
    isStreaming: isStreaming,
    metadata: metadata,
  );

  static MobileCodexTimelineCell? _find(
    List<MobileCodexTimelineCell> cells,
    String id,
  ) {
    for (final cell in cells) {
      if (cell.id == id) return cell;
    }
    return null;
  }

  static List<MobileCodexTimelineCell> _upsert(
    List<MobileCodexTimelineCell> cells,
    MobileCodexTimelineCell next,
  ) {
    var index = cells.indexWhere((cell) => cell.id == next.id);
    if (index < 0 && next.itemId != null && next.turnId != null) {
      final provisionalIds = <String>{
        '${next.kind}-${next.turnId}',
        if (next.kind == 'assistantMessage' || next.kind == 'progressText')
          'assistant-${next.turnId}',
      };
      index = cells.indexWhere(
        (cell) =>
            provisionalIds.contains(cell.id) &&
            cell.itemId == null &&
            cell.kind == next.kind,
      );
    }
    if (index < 0) return <MobileCodexTimelineCell>[...cells, next];
    final result = <MobileCodexTimelineCell>[...cells];
    final previous = result[index];
    result[index] = next.copyWith(
      id: next.id,
      itemId: next.itemId ?? previous.itemId,
      turnId: next.turnId ?? previous.turnId,
      updatedAt: DateTime.now().toUtc(),
      title: next.title ?? previous.title,
      subtitle: next.subtitle ?? previous.subtitle,
      markdownText: next.markdownText ?? previous.markdownText,
      renderedMarkdownText:
          next.renderedMarkdownText ?? previous.renderedMarkdownText,
      detailsText: next.detailsText ?? previous.detailsText,
      metadata: <String, Object?>{...previous.metadata, ...next.metadata},
      isCollapsed: next.isCollapsed || previous.isCollapsed,
    );
    return result;
  }
}

String? _sourceFor(String lower) {
  if (lower == 'item/agentmessage/delta' ||
      lower.contains('agentmessage') && lower.contains('delta')) {
    return 'agent';
  }
  if (lower.contains('reasoning') && lower.contains('delta')) {
    return 'reasoning';
  }
  if (lower == 'item/commandexecution/outputdelta' ||
      lower == 'item/filechange/outputdelta' ||
      lower == 'item/mcptoolcall/outputdelta' ||
      lower == 'item/websearch/outputdelta' ||
      lower == 'item/plan/delta' ||
      lower == 'item/commandexecution/terminalinteraction' ||
      lower == 'item/mcptoolcall/progress' ||
      lower.contains('outputdelta')) {
    return 'output';
  }
  return null;
}

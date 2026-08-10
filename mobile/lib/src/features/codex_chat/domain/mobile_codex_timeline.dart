part of 'mobile_codex_state.dart';

/// Rebuilds a stable mobile timeline when an older host only persisted raw
/// app-server events and has no timeline projection yet.
abstract final class MobileCodexTimelineReducer {
  static List<MobileCodexTimelineCell> reduce(
    List<MobileCodexTimelineCell> cells,
    Map<String, Object?> message,
  ) {
    final rawMethod = message['method']?.toString() ?? '';
    final method = switch (rawMethod) {
      'codex/event/item_started' => 'item/started',
      'codex/event/item_completed' => 'item/completed',
      'codex/event/task_complete' => 'turn/completed',
      _ => rawMethod,
    };
    final params = _map(message['params']);
    final legacy = _map(params['msg']);
    final item = _map(params['item'] ?? legacy['item']);
    final turnId = _first(<Object?>[
      params['turnId'],
      _map(params['turn'])['id'],
      item['turnId'],
      item['turn_id'],
      legacy['turnId'],
      legacy['turn_id'],
      message['turnId'],
    ]);
    final itemId = _first(<Object?>[
      params['itemId'],
      params['item_id'],
      item['id'],
      params['id'],
    ]);
    final lower = method.toLowerCase();
    final type = (item['type'] ?? params['type'] ?? '')
        .toString()
        .toLowerCase();

    if (method == 'thread/compacted') {
      return _reduceLegacyMobileContextCompaction(cells, turnId);
    }

    if (rawMethod == 'codex/event/task_complete') {
      final text = _first(<Object?>[
        legacy['last_agent_message'],
        legacy['lastAgentMessage'],
      ]);
      var next = cells;
      if (text.isNotEmpty && turnId.isNotEmpty) {
        next = _upsert(
          next,
          _cell(
            id: 'assistant-$turnId',
            turnId: turnId,
            kind: 'assistantMessage',
            status: 'completed',
            title: 'Codex',
            markdownText: text,
          ),
        );
      }
      return _close(next, turnId, 'completed');
    }
    if (method == 'turn/started' || method == 'turn/created') {
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
    if (method == 'turn/completed' ||
        method == 'turn/failed' ||
        method == 'turn/aborted' ||
        method == 'turn/interrupted') {
      return _close(
        cells,
        turnId,
        method == 'turn/failed' ? 'failed' : 'completed',
      );
    }
    if (method == 'turn/diff/updated') {
      final delta = _first(<Object?>[
        params['diff'],
        params['delta'],
        params['text'],
      ]);
      final hasSnapshot =
          params.containsKey('diff') ||
          params.containsKey('delta') ||
          params.containsKey('text');
      if (turnId.isEmpty || !hasSnapshot) return cells;
      final id = 'diff-$turnId';
      final existing = _find(cells, id);
      if (existing?.metadata['lastDelta'] == delta) return cells;
      return _upsert(
        cells,
        _cell(
          id: id,
          turnId: turnId,
          kind: 'diff',
          status: 'inProgress',
          title: 'File changes',
          detailsText: delta,
          isStreaming: true,
          metadata: <String, Object?>{
            ...?existing?.metadata,
            'lastDelta': delta,
          },
        ),
      );
    }

    final source = _sourceFor(lower);
    if (source != null) {
      return _appendDelta(
        cells,
        turnId: turnId,
        itemId: itemId,
        item: item,
        params: params,
        legacy: legacy,
        source: source,
      );
    }
    if ((lower.contains('subagent') || lower.contains('collab')) &&
        turnId.isNotEmpty) {
      final delta = _first(<Object?>[
        params['delta'],
        params['text'],
        params['summary'],
        params['message'],
        legacy['summary'],
        legacy['message'],
      ]);
      final id = itemId.isEmpty ? 'subAgent-$turnId' : 'item-$itemId';
      final existing = _find(cells, id);
      if (existing?.metadata['lastDelta'] == delta) return cells;
      return _upsert(
        cells,
        _cell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: 'subAgent',
          status: lower.contains('completed') || lower.contains('end')
              ? 'completed'
              : 'inProgress',
          title: 'Sub-agent',
          markdownText: delta.isEmpty
              ? existing?.markdownText
              : '${existing?.markdownText ?? ''}$delta',
          isStreaming: !lower.contains('completed') && !lower.contains('end'),
          metadata: <String, Object?>{
            ...?existing?.metadata,
            if (delta.isNotEmpty) 'lastDelta': delta,
          },
        ),
      );
    }
    if (method == 'item/started' ||
        method == 'item/completed' ||
        method == 'item/updated') {
      if (turnId.isEmpty) return cells;
      final baseKind = _kindFor(type, lower);
      final provisionalId = itemId.isEmpty
          ? '$baseKind-$turnId'
          : 'item-$itemId';
      final existing = _find(cells, provisionalId);
      final phase = _first(<Object?>[
        item['phase'],
        params['phase'],
        existing?.metadata['streamPhase'],
      ]);
      final isAgent =
          type.contains('agentmessage') || type.contains('assistant');
      final kind = isAgent && phase == 'commentary' ? 'progressText' : baseKind;
      final id = itemId.isEmpty ? '$kind-$turnId' : 'item-$itemId';
      final current = _find(cells, id) ?? existing;
      final statusRaw = _first(<Object?>[
        item['status'],
        params['status'],
      ]).toLowerCase();
      final status = statusRaw.contains('fail')
          ? 'failed'
          : statusRaw.contains('declin')
          ? 'declined'
          : method == 'item/completed'
          ? 'completed'
          : 'inProgress';
      final details = _mobileCodexItemDetails(item);
      return _upsert(
        cells,
        _cell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: kind,
          status: status,
          title: type.contains('contextcompaction')
              ? mobileCodexContextCompactionTitle(status)
              : _titleFor(type, lower, item),
          subtitle: _first(<Object?>[
            item['command'],
            item['name'],
            item['path'],
          ]),
          markdownText: _first(<Object?>[
            item['text'],
            item['content'],
            item['summary'],
            item['message'],
          ]),
          detailsText: details.isEmpty ? null : details,
          isStreaming: method != 'item/completed',
          metadata: <String, Object?>{
            ...?current?.metadata,
            ..._mobileCodexItemMetadata(item),
            if (isAgent && phase.isNotEmpty) 'streamPhase': phase,
          },
        ),
      );
    }
    if (method == 'error' ||
        method == 'stream/error' ||
        method == 'stream_error') {
      final text = _first(<Object?>[
        params['message'],
        params['error'],
        message['error'],
      ]);
      if (text.isEmpty) return cells;
      return <MobileCodexTimelineCell>[
        ...cells,
        _cell(
          id: 'error-${DateTime.now().microsecondsSinceEpoch}',
          turnId: turnId.isEmpty ? null : turnId,
          kind: 'systemNotice',
          status: 'failed',
          title: 'Codex error',
          markdownText: text,
        ),
      ];
    }
    if (lower.contains('review') && turnId.isNotEmpty) {
      final review = _first(<Object?>[params['review'], params['text']]);
      return _upsert(
        cells,
        _cell(
          id: itemId.isEmpty ? 'review-$turnId' : 'item-$itemId',
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: 'toolCall',
          status: 'completed',
          title: lower.contains('enter')
              ? 'Entered review mode'
              : 'Exited review mode',
          detailsText: review.isEmpty ? null : review,
          metadata: <String, Object?>{
            'itemType': lower.contains('enter')
                ? 'enteredReviewMode'
                : 'exitedReviewMode',
          },
        ),
      );
    }
    return cells;
  }

  static List<MobileCodexTimelineCell> _appendDelta(
    List<MobileCodexTimelineCell> cells, {
    required String turnId,
    required String itemId,
    required Map<String, Object?> item,
    required Map<String, Object?> params,
    required Map<String, Object?> legacy,
    required String source,
  }) {
    if (turnId.isEmpty) return cells;
    final values = <Object?>[
      params['delta'],
      params['text'],
      legacy['delta'],
      legacy['text'],
    ];
    if (source == 'output') {
      values.addAll(<Object?>[params['output'], params['interaction']]);
    } else if (source == 'agent') {
      values.add(legacy['message']);
    }
    final delta = _rawFirst(values);
    if (delta.isEmpty) return cells;
    final itemType = item['type']?.toString().toLowerCase() ?? '';
    final provisional = itemId.isEmpty
        ? '${_kindFor(itemType, source)}-$turnId'
        : 'item-$itemId';
    final existing = _find(cells, provisional);
    final phase = _first(<Object?>[
      item['phase'],
      params['phase'],
      existing?.metadata['streamPhase'],
    ]);
    final kind = source == 'agent'
        ? phase.isEmpty || phase == 'final_answer' || phase == 'final'
              ? 'assistantMessage'
              : 'progressText'
        : source == 'reasoning'
        ? 'reasoning'
        : _kindFor(itemType, source);
    final id = itemId.isEmpty ? '$kind-$turnId' : 'item-$itemId';
    final current = _find(cells, id);
    if (current?.metadata['lastDelta'] == delta) return cells;
    return _upsert(
      cells,
      _cell(
        id: id,
        itemId: itemId.isEmpty ? null : itemId,
        turnId: turnId,
        kind: kind,
        status: 'inProgress',
        title: source == 'reasoning'
            ? 'Reasoning'
            : source == 'output'
            ? _titleFor(itemType, source, item)
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
    final index = cells.indexWhere((cell) => cell.id == next.id);
    if (index < 0) return <MobileCodexTimelineCell>[...cells, next];
    final result = <MobileCodexTimelineCell>[...cells];
    final previous = result[index];
    result[index] = next.copyWith(
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

import 'codex_timeline_cell.dart';

export 'codex_timeline_cell.dart';

part 'codex_timeline_helpers.dart';
part 'codex_timeline_lifecycle.dart';
part 'codex_timeline_modern.dart';

/// The host and Flutter clients use this reducer as a compatibility oracle.
/// It deliberately keys cells by app-server item IDs, so deltas update one row
/// instead of creating a card for every notification.
abstract final class CodexTimelineReducer {
  static List<CodexTimelineCell> reduce(
    List<CodexTimelineCell> cells,
    Map<String, Object?> message, {
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now().toUtc()).toUtc();
    final rawMethod = message['method']?.toString() ?? '';
    final method = switch (rawMethod) {
      'codex/event/item_started' => 'item/started',
      'codex/event/item_completed' => 'item/completed',
      'codex/event/task_complete' => 'turn/completed',
      'codex/event/token_count' => 'token_count',
      _ => rawMethod,
    };
    final params = _map(message['params']);
    final legacyMessage = _map(params['msg']);
    final item = _map(params['item'] ?? legacyMessage['item']);
    final turnId = _firstString(<Object?>[
      params['turnId'],
      _map(params['turn'])['id'],
      item['turnId'],
      item['turn_id'],
      legacyMessage['turnId'],
      legacyMessage['turn_id'],
      message['turnId'],
    ]);
    final itemId = _firstString(<Object?>[
      params['itemId'],
      item['id'],
      params['id'],
      item['itemId'],
    ]);
    final lowerMethod = method.toLowerCase();
    final type = (item['type'] ?? params['type'] ?? '')
        .toString()
        .toLowerCase();
    final modern = _reduceModernCodexNotification(
      cells,
      method: method,
      params: params,
      turnId: turnId,
      itemId: itemId,
      timestamp: timestamp,
    );
    if (modern != null) return modern;

    final event = (
      cells: cells,
      message: message,
      rawMethod: rawMethod,
      method: method,
      params: params,
      legacyMessage: legacyMessage,
      item: item,
      turnId: turnId,
      itemId: itemId,
      lowerMethod: lowerMethod,
      type: type,
      timestamp: timestamp,
    );
    return _reduceLegacyTaskCompletion(event) ??
        _reduceTurnLifecycle(event) ??
        _reduceTurnDiff(event) ??
        _reduceAssistantDelta(event) ??
        _reduceReasoningDelta(event) ??
        _reduceItemOutputDelta(event) ??
        _reduceSubAgentEvent(event) ??
        _reduceItemLifecycle(event) ??
        _reduceError(event) ??
        _reduceReview(event) ??
        cells;
  }
}

typedef _CodexTimelineEvent = ({
  List<CodexTimelineCell> cells,
  Map<String, Object?> message,
  String rawMethod,
  String method,
  Map<String, Object?> params,
  Map<String, Object?> legacyMessage,
  Map<String, Object?> item,
  String turnId,
  String itemId,
  String lowerMethod,
  String type,
  DateTime timestamp,
});

List<CodexTimelineCell>? _reduceLegacyTaskCompletion(
  _CodexTimelineEvent event,
) {
  if (event.rawMethod != 'codex/event/task_complete') return null;
  final text = _firstString(<Object?>[
    event.legacyMessage['last_agent_message'],
    event.legacyMessage['lastAgentMessage'],
  ]);
  var next = event.cells;
  if (text.isNotEmpty && event.turnId.isNotEmpty) {
    final existing = _find(next, 'assistant-${event.turnId}');
    next = _upsert(
      next,
      _newCell(
        id: 'assistant-${event.turnId}',
        turnId: event.turnId,
        kind: .assistantMessage,
        status: .completed,
        timestamp: event.timestamp,
        title: 'Codex',
        markdownText: text,
        isStreaming: false,
        metadata: existing?.metadata ?? const <String, Object?>{},
      ),
    );
  }
  final completed = <CodexTimelineCell>[
    for (final cell in next)
      if (cell.turnId == event.turnId && cell.isStreaming)
        cell.copyWith(
          status: .completed,
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

List<CodexTimelineCell>? _reduceTurnDiff(_CodexTimelineEvent event) {
  if (event.method != 'turn/diff/updated') return null;
  final diff = _firstString(<Object?>[
    event.params['diff'],
    event.params['delta'],
    event.params['text'],
  ]);
  final hasSnapshot =
      event.params.containsKey('diff') ||
      event.params.containsKey('delta') ||
      event.params.containsKey('text');
  if (event.turnId.isEmpty || !hasSnapshot) return event.cells;
  final id = 'diff-${event.turnId}';
  final existing = _find(event.cells, id);
  if (existing?.metadata['lastDelta'] == diff) return event.cells;
  return _upsert(
    event.cells,
    _newCell(
      id: id,
      turnId: event.turnId,
      kind: .diff,
      status: .inProgress,
      timestamp: event.timestamp,
      title: 'File changes',
      detailsText: diff,
      isStreaming: true,
      metadata: <String, Object?>{...?existing?.metadata, 'lastDelta': diff},
    ),
  );
}

List<CodexTimelineCell>? _reduceAssistantDelta(_CodexTimelineEvent event) {
  if (event.method != 'item/agentMessage/delta' &&
      !(event.lowerMethod.contains('agentmessage') &&
          event.lowerMethod.contains('delta'))) {
    return null;
  }
  final delta = _firstString(<Object?>[
    event.params['delta'],
    event.params['text'],
    event.legacyMessage['delta'],
    event.legacyMessage['text'],
    event.legacyMessage['message'],
  ]);
  if (delta.isEmpty || event.turnId.isEmpty) return event.cells;
  final id = event.itemId.isEmpty
      ? 'assistant-${event.turnId}'
      : 'item-${event.itemId}';
  final existing = _find(event.cells, id);
  final phase = _firstString(<Object?>[
    event.item['phase'],
    event.params['phase'],
    existing?.metadata['streamPhase'],
  ]);
  final finalAnswer =
      phase.isEmpty || phase == 'final_answer' || phase == 'final';
  final current = existing?.markdownText ?? '';
  final existingKind = existing?.kind;
  final metadata = <String, Object?>{
    ...?existing?.metadata,
    'streamPhase': finalAnswer ? 'final_answer' : 'commentary',
    'lastDelta': delta,
  };
  if (existing != null && existing.metadata['lastDelta'] == delta) {
    return event.cells;
  }
  return _upsert(
    event.cells,
    _newCell(
      id: id,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: finalAnswer || existingKind == CodexTimelineKind.assistantMessage
          ? CodexTimelineKind.assistantMessage
          : CodexTimelineKind.progressText,
      status: .inProgress,
      timestamp: event.timestamp,
      markdownText: '$current$delta',
      isStreaming: true,
      metadata: metadata,
    ),
  );
}

List<CodexTimelineCell>? _reduceReasoningDelta(_CodexTimelineEvent event) {
  if (event.method != 'item/reasoning/summaryTextDelta' &&
      event.method != 'item/reasoning/textDelta' &&
      !(event.lowerMethod.contains('reasoning') &&
          event.lowerMethod.contains('delta'))) {
    return null;
  }
  final delta = _firstString(<Object?>[
    event.params['delta'],
    event.params['text'],
    event.legacyMessage['delta'],
    event.legacyMessage['text'],
  ]);
  if (delta.isEmpty || event.turnId.isEmpty) return event.cells;
  final id = event.itemId.isEmpty
      ? 'reasoning-${event.turnId}'
      : 'item-${event.itemId}';
  final existing = _find(event.cells, id);
  if (existing != null && existing.metadata['lastDelta'] == delta) {
    return event.cells;
  }
  return _upsert(
    event.cells,
    _newCell(
      id: id,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: .reasoning,
      status: .inProgress,
      timestamp: event.timestamp,
      title: 'Reasoning',
      markdownText: '${existing?.markdownText ?? ''}$delta',
      isStreaming: true,
      metadata: <String, Object?>{...?existing?.metadata, 'lastDelta': delta},
    ),
  );
}

List<CodexTimelineCell>? _reduceItemOutputDelta(_CodexTimelineEvent event) {
  if (event.method != 'item/commandExecution/outputDelta' &&
      event.method != 'item/fileChange/outputDelta' &&
      event.method != 'item/mcpToolCall/outputDelta' &&
      event.method != 'item/webSearch/outputDelta' &&
      event.method != 'item/plan/delta' &&
      event.method != 'item/commandExecution/terminalInteraction' &&
      event.method != 'item/mcpToolCall/progress' &&
      !event.lowerMethod.contains('outputdelta')) {
    return null;
  }
  final delta = _firstString(<Object?>[
    event.params['delta'],
    event.params['text'],
    event.params['output'],
    event.params['interaction'],
    event.legacyMessage['delta'],
    event.legacyMessage['text'],
  ]);
  if (delta.isEmpty || event.turnId.isEmpty) return event.cells;
  final provisionalKind = _kindFor(event.type, event.lowerMethod);
  final id = event.itemId.isEmpty
      ? '${provisionalKind.name}-${event.turnId}'
      : 'item-${event.itemId}';
  final existing = _find(event.cells, id);
  final kind = existing?.kind ?? provisionalKind;
  if (existing?.metadata['lastDelta'] == delta) return event.cells;
  final resolvedId = event.itemId.isEmpty
      ? '${kind.name}-${event.turnId}'
      : 'item-${event.itemId}';
  final details = existing?.detailsText ?? existing?.markdownText ?? '';
  return _upsert(
    event.cells,
    _newCell(
      id: resolvedId,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: kind,
      status: .inProgress,
      timestamp: event.timestamp,
      title: _titleFor(event.type, event.lowerMethod),
      detailsText: '$details$delta',
      isStreaming: true,
      metadata: <String, Object?>{...?existing?.metadata, 'lastDelta': delta},
    ),
  );
}

List<CodexTimelineCell>? _reduceSubAgentEvent(_CodexTimelineEvent event) {
  if ((!event.lowerMethod.contains('subagent') &&
          !event.lowerMethod.contains('collab')) ||
      event.turnId.isEmpty) {
    return null;
  }
  final delta = _firstString(<Object?>[
    event.params['delta'],
    event.params['text'],
    event.params['summary'],
    event.params['message'],
    event.legacyMessage['summary'],
    event.legacyMessage['message'],
  ]);
  final id = event.itemId.isEmpty
      ? 'subAgent-${event.turnId}'
      : 'item-${event.itemId}';
  final existing = _find(event.cells, id);
  if (existing?.metadata['lastDelta'] == delta) return event.cells;
  return _upsert(
    event.cells,
    _newCell(
      id: id,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: .subAgent,
      status:
          event.lowerMethod.contains('completed') ||
              event.lowerMethod.contains('end')
          ? CodexTimelineStatus.completed
          : CodexTimelineStatus.inProgress,
      timestamp: event.timestamp,
      title: 'Sub-agent',
      markdownText: delta.isEmpty
          ? existing?.markdownText
          : '${existing?.markdownText ?? ''}$delta',
      isStreaming:
          !event.lowerMethod.contains('completed') &&
          !event.lowerMethod.contains('end'),
      metadata: <String, Object?>{
        ...?existing?.metadata,
        if (delta.isNotEmpty) 'lastDelta': delta,
      },
    ),
  );
}

List<CodexTimelineCell>? _reduceError(_CodexTimelineEvent event) {
  if (event.method != 'error' &&
      event.method != 'stream/error' &&
      event.method != 'stream_error') {
    return null;
  }
  final text = _firstString(<Object?>[
    event.params['message'],
    event.params['error'],
    event.message['error'],
  ]);
  if (text.isEmpty) return event.cells;
  return <CodexTimelineCell>[
    ...event.cells,
    _newCell(
      id: 'error-${event.timestamp.microsecondsSinceEpoch}',
      turnId: event.turnId.isEmpty ? null : event.turnId,
      kind: .systemNotice,
      status: .failed,
      timestamp: event.timestamp,
      title: 'Codex error',
      markdownText: text,
    ),
  ];
}

List<CodexTimelineCell>? _reduceReview(_CodexTimelineEvent event) {
  if (!event.method.contains('review') || event.turnId.isEmpty) return null;
  final title = event.method.contains('enter')
      ? 'Entered review mode'
      : 'Exited review mode';
  final review = _firstString(<Object?>[
    event.params['review'],
    event.item['review'],
    event.params['text'],
  ]);
  final id = event.itemId.isEmpty
      ? 'review-${event.turnId}'
      : 'item-${event.itemId}';
  final result = _upsert(
    event.cells,
    _newCell(
      id: id,
      itemId: event.itemId.isEmpty ? null : event.itemId,
      turnId: event.turnId,
      kind: .toolCall,
      status: .completed,
      timestamp: event.timestamp,
      title: title,
      detailsText: review.isEmpty ? null : review,
      metadata: <String, Object?>{
        'itemType': event.method.contains('enter')
            ? 'enteredReviewMode'
            : 'exitedReviewMode',
      },
    ),
  );
  if (review.isEmpty) return result;
  return <CodexTimelineCell>[
    ...result,
    _newCell(
      id: 'review-body-${event.turnId}',
      turnId: event.turnId,
      kind: .progressText,
      status: .completed,
      timestamp: event.timestamp,
      markdownText: review,
      metadata: <String, Object?>{
        CodexTimelineMetadata.uiPlacement: CodexTimelineMetadata.outsideWorked,
      },
    ),
  ];
}

import 'dart:convert';

import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';

SessionState appendOptimisticUserMessage(
  SessionState state, {
  required String text,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final cell = TimelineCell(
    id: 'user-${timestamp.microsecondsSinceEpoch}',
    turnId: null,
    kind: TimelineCellKind.userMessage,
    status: TimelineCellStatus.completed,
    createdAt: timestamp,
    updatedAt: timestamp,
    markdownText: text,
  );

  return state.copyWith(
    timelineCells: <TimelineCell>[...state.timelineCells, cell],
  );
}

SessionState reduceNotification(
  SessionState state,
  SessionNotificationEvent event, {
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final params = _asMap(event.payload['params']);
  final next = _appendRawLog(state, event);

  switch (event.method) {
    case 'turn/started':
      return _onTurnStarted(next, params, timestamp);
    case 'turn/completed':
      return _onTurnCompleted(next, params, timestamp);
    case 'item/started':
      return _onItemStarted(next, params, timestamp);
    case 'item/completed':
      return _onItemCompleted(next, params, timestamp);
    case 'item/agentMessage/delta':
      return _onAssistantDelta(next, params, timestamp);
    case 'item/reasoning/summaryTextDelta':
      return _onReasoningDelta(next, params, timestamp);
    case 'item/commandExecution/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'Ran command',
      );
    case 'item/fileChange/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'file change',
      );
    case 'item/mcpToolCall/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'mcp tool call',
      );
    case 'item/webSearch/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'web search',
      );
    case 'item/plan/delta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'plan',
      );
    default:
      return next;
  }
}

SessionState _appendRawLog(SessionState state, SessionNotificationEvent event) {
  final text = '${event.method}: ${event.payload['params'] ?? ''}';
  final nextLog = <String>[...state.activityLog, text];
  final clipped = nextLog.length <= 200
      ? nextLog
      : nextLog.sublist(nextLog.length - 200);
  return state.copyWith(activityLog: clipped);
}

SessionState _onTurnStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turn = _asMap(params['turn']);
  final turnId = _asString(turn['id']);
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final pendingUserCellId = index.pendingUserCellIdQueue.isEmpty
      ? null
      : index.pendingUserCellIdQueue.last;

  if (pendingUserCellId != null) {
    final userIndex = _findCellById(cells, pendingUserCellId);
    if (userIndex != -1) {
      cells[userIndex] = cells[userIndex].copyWith(
        turnId: turnId,
        updatedAt: timestamp,
      );
    }
  }

  return state.copyWith(timelineCells: cells, activeTurnId: turnId);
}

SessionState _onTurnCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turn = _asMap(params['turn']);
  final turnId = _asString(turn['id']);
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell.turnId != turnId) {
      continue;
    }

    if (cell.kind == TimelineCellKind.assistantMessage && cell.isStreaming) {
      cells[i] = cell.copyWith(
        isStreaming: false,
        status: _statusFromString(_asString(turn['status'])) ?? cell.status,
        updatedAt: timestamp,
      );
      continue;
    }

    if (_isSecondaryKind(cell.kind)) {
      cells[i] = cell.copyWith(isCollapsed: true, updatedAt: timestamp);
    }
  }

  final durationFromCells = _computeTurnDurationFromCells(
    cells,
    turnId: turnId,
    turnCompletedAt: timestamp,
  );
  final separatorId = 'turn-separator-$turnId';
  final separatorMetadata = <String, dynamic>{...turn};
  if (durationFromCells != null && durationFromCells > 0) {
    separatorMetadata['computedDurationMs'] = durationFromCells;
  }
  final separator = TimelineCell(
    id: separatorId,
    turnId: turnId,
    kind: TimelineCellKind.turnSeparator,
    status:
        _statusFromString(_asString(turn['status'])) ?? TimelineCellStatus.info,
    createdAt: timestamp,
    updatedAt: timestamp,
    title: _separatorTitle(turn),
    subtitle: _separatorSubtitle(separatorMetadata),
    metadata: separatorMetadata,
  );

  final existingSeparatorIndex = _findCellById(cells, separatorId);
  if (existingSeparatorIndex == -1) {
    cells.add(separator);
  } else {
    cells[existingSeparatorIndex] = separator;
  }

  var clearStreaming = false;
  final activeStreamingId = state.activeStreamingAssistantCellId;
  if (activeStreamingId != null) {
    final activeIndex = _findCellById(cells, activeStreamingId);
    if (activeIndex != -1 && cells[activeIndex].turnId == turnId) {
      clearStreaming = true;
    }
  }

  return state.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: clearStreaming,
    clearActiveTurnId: state.activeTurnId == turnId,
  );
}

SessionState _onAssistantDelta(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  final delta = _asString(params['delta']) ?? '';
  if (turnId == null || turnId.isEmpty || delta.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  var assistantCellId = index.assistantCellIdByTurn[turnId];
  assistantCellId ??= itemId != null ? index.cellIdByItemId[itemId] : null;
  assistantCellId ??= itemId ?? 'assistant-$turnId';

  final existingIndex = _findCellById(cells, assistantCellId);
  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: assistantCellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.assistantMessage,
        status: TimelineCellStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        isStreaming: true,
        markdownText: delta,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      status: TimelineCellStatus.inProgress,
      isStreaming: true,
      markdownText: '${existing.markdownText ?? ''}$delta',
      updatedAt: timestamp,
    );
  }

  return state.copyWith(
    timelineCells: cells,
    activeStreamingAssistantCellId: assistantCellId,
    activeTurnId: turnId,
  );
}

SessionState _onReasoningDelta(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId =
      _asString(params['itemId']) ??
      (turnId == null ? null : 'reasoning-$turnId');
  final delta = _asString(params['delta']) ?? '';
  if (turnId == null || turnId.isEmpty || itemId == null || delta.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = _findCellById(cells, cellId);

  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.reasoning,
        status: TimelineCellStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        markdownText: delta,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: TimelineCellKind.reasoning,
      status: TimelineCellStatus.inProgress,
      isCollapsed: false,
      markdownText: '${existing.markdownText ?? ''}$delta',
      updatedAt: timestamp,
    );
  }

  _collapseOtherSecondaryCellsForTurn(
    cells,
    turnId: turnId,
    exceptCellId: cellId,
    timestamp: timestamp,
  );

  return state.copyWith(timelineCells: cells, activeTurnId: turnId);
}

SessionState _onToolOutputDelta(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
  required String fallbackTitle,
}) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  final delta = _asString(params['delta']) ?? '';
  if (turnId == null || turnId.isEmpty || itemId == null || delta.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = _findCellById(cells, cellId);

  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.toolCall,
        status: TimelineCellStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        title: fallbackTitle,
        detailsText: delta,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: existing.kind == TimelineCellKind.reasoning
          ? TimelineCellKind.reasoning
          : TimelineCellKind.toolCall,
      status: TimelineCellStatus.inProgress,
      isCollapsed: false,
      detailsText: '${existing.detailsText ?? ''}$delta',
      updatedAt: timestamp,
    );
  }

  _collapseOtherSecondaryCellsForTurn(
    cells,
    turnId: turnId,
    exceptCellId: cellId,
    timestamp: timestamp,
  );

  return state.copyWith(timelineCells: cells, activeTurnId: turnId);
}

SessionState _onItemStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final item = _asMap(params['item']);
  final turnId = _asString(params['turnId']) ?? _asString(item['turnId']);
  final itemId = _asString(item['id']);
  final itemType = _asString(item['type']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      itemType == null ||
      itemType.isEmpty) {
    return state;
  }

  if (itemType == 'agentMessage' || itemType == 'userMessage') {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = _findCellById(cells, cellId);
  final kind = itemType == 'reasoning'
      ? TimelineCellKind.reasoning
      : TimelineCellKind.toolCall;

  final title = _itemTitle(itemType, item);
  final subtitle = _itemSubtitle(itemType, item);
  final markdownText = kind == TimelineCellKind.reasoning
      ? (_reasoningSummary(item).isEmpty ? null : _reasoningSummary(item))
      : null;
  final detailsText = kind == TimelineCellKind.toolCall
      ? _itemDetails(itemType, item)
      : null;

  final candidate = TimelineCell(
    id: cellId,
    turnId: turnId,
    itemId: itemId,
    kind: kind,
    status:
        _statusFromString(_asString(item['status'])) ??
        TimelineCellStatus.inProgress,
    createdAt: timestamp,
    updatedAt: timestamp,
    isCollapsed: false,
    title: title,
    subtitle: subtitle,
    markdownText: markdownText,
    detailsText: detailsText,
    metadata: item,
  );

  if (existingIndex == -1) {
    cells.add(candidate);
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: candidate.kind,
      status: candidate.status,
      title: candidate.title,
      subtitle: candidate.subtitle,
      markdownText: candidate.markdownText,
      detailsText: candidate.detailsText,
      metadata: candidate.metadata,
      isCollapsed: false,
      updatedAt: timestamp,
    );
  }

  _collapseOtherSecondaryCellsForTurn(
    cells,
    turnId: turnId,
    exceptCellId: cellId,
    timestamp: timestamp,
  );

  return state.copyWith(timelineCells: cells, activeTurnId: turnId);
}

SessionState _onItemCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final item = _asMap(params['item']);
  final turnId = _asString(params['turnId']) ?? _asString(item['turnId']);
  final itemId = _asString(item['id']);
  final itemType = _asString(item['type']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      itemType == null ||
      itemType.isEmpty) {
    return state;
  }

  if (itemType == 'userMessage') {
    return state;
  }

  if (itemType == 'agentMessage') {
    return _onAssistantItemCompleted(
      state,
      turnId: turnId,
      itemId: itemId,
      item: item,
      timestamp: timestamp,
    );
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = _findCellById(cells, cellId);
  final kind = itemType == 'reasoning'
      ? TimelineCellKind.reasoning
      : TimelineCellKind.toolCall;
  final status =
      _statusFromString(_asString(item['status'])) ??
      TimelineCellStatus.completed;

  final title = _itemTitle(itemType, item);
  final subtitle = _itemSubtitle(itemType, item);
  final reasoningText = _reasoningSummary(item);
  final markdownText = kind == TimelineCellKind.reasoning
      ? (reasoningText.isEmpty ? null : reasoningText)
      : null;
  final detailsText = kind == TimelineCellKind.toolCall
      ? _itemDetails(itemType, item)
      : _itemDetails(itemType, item);

  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: kind,
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
        isCollapsed: false,
        title: title,
        subtitle: subtitle,
        markdownText: markdownText,
        detailsText: detailsText,
        metadata: item,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    final mergedReasoning = kind == TimelineCellKind.reasoning
        ? _mergeFinalText(existing.markdownText ?? '', markdownText ?? '')
        : existing.markdownText;
    final mergedDetails = _mergeOptionalText(existing.detailsText, detailsText);

    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: kind,
      status: status,
      title: title,
      subtitle: subtitle,
      markdownText: mergedReasoning,
      detailsText: mergedDetails,
      metadata: item,
      updatedAt: timestamp,
    );
  }

  return state.copyWith(timelineCells: cells, activeTurnId: turnId);
}

SessionState _onAssistantItemCompleted(
  SessionState state, {
  required String turnId,
  required String itemId,
  required Map<String, dynamic> item,
  required DateTime timestamp,
}) {
  final finalText = _assistantFinalText(item);
  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);

  var assistantCellId = index.assistantCellIdByTurn[turnId];
  assistantCellId ??= index.cellIdByItemId[itemId];
  assistantCellId ??= itemId;

  final existingIndex = _findCellById(cells, assistantCellId);
  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: assistantCellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.assistantMessage,
        status:
            _statusFromString(_asString(item['status'])) ??
            TimelineCellStatus.completed,
        createdAt: timestamp,
        updatedAt: timestamp,
        isStreaming: false,
        markdownText: finalText,
        metadata: item,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      status: _statusFromString(_asString(item['status'])) ?? existing.status,
      isStreaming: false,
      markdownText: _mergeFinalText(existing.markdownText ?? '', finalText),
      metadata: item,
      updatedAt: timestamp,
    );
  }

  final shouldClearStreaming =
      state.activeStreamingAssistantCellId == assistantCellId;
  return state.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: shouldClearStreaming,
  );
}

class _CellIndex {
  const _CellIndex({
    required this.assistantCellIdByTurn,
    required this.cellIdByItemId,
    required this.pendingUserCellIdQueue,
  });

  final Map<String, String> assistantCellIdByTurn;
  final Map<String, String> cellIdByItemId;
  final List<String> pendingUserCellIdQueue;
}

_CellIndex _buildCellIndex(List<TimelineCell> cells) {
  final assistantCellIdByTurn = <String, String>{};
  final cellIdByItemId = <String, String>{};
  final pendingUserCellIdQueue = <String>[];

  for (final cell in cells) {
    if (cell.turnId != null && cell.kind == TimelineCellKind.assistantMessage) {
      assistantCellIdByTurn[cell.turnId!] = cell.id;
    }
    if (cell.itemId != null && cell.itemId!.isNotEmpty) {
      cellIdByItemId[cell.itemId!] = cell.id;
    }
    if (cell.kind == TimelineCellKind.userMessage && cell.turnId == null) {
      pendingUserCellIdQueue.add(cell.id);
    }
  }

  return _CellIndex(
    assistantCellIdByTurn: assistantCellIdByTurn,
    cellIdByItemId: cellIdByItemId,
    pendingUserCellIdQueue: pendingUserCellIdQueue,
  );
}

int _findCellById(List<TimelineCell> cells, String id) {
  for (var i = 0; i < cells.length; i++) {
    if (cells[i].id == id) {
      return i;
    }
  }
  return -1;
}

int? _computeTurnDurationFromCells(
  List<TimelineCell> cells, {
  required String turnId,
  required DateTime turnCompletedAt,
}) {
  var startMs = -1;
  for (final cell in cells) {
    if (cell.turnId != turnId || cell.kind == TimelineCellKind.turnSeparator) {
      continue;
    }
    final candidateStartMs = cell.createdAt.millisecondsSinceEpoch;
    if (startMs == -1 || candidateStartMs < startMs) {
      startMs = candidateStartMs;
    }
  }
  if (startMs == -1) {
    return null;
  }
  final endMs = turnCompletedAt.millisecondsSinceEpoch;
  final duration = endMs - startMs;
  return duration > 0 ? duration : null;
}

void _collapseOtherSecondaryCellsForTurn(
  List<TimelineCell> cells, {
  required String turnId,
  required String exceptCellId,
  required DateTime timestamp,
}) {
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell.turnId != turnId || cell.id == exceptCellId) {
      continue;
    }
    if (!_isSecondaryKind(cell.kind) || cell.isCollapsed) {
      continue;
    }
    cells[i] = cell.copyWith(isCollapsed: true, updatedAt: timestamp);
  }
}

bool _isSecondaryKind(TimelineCellKind kind) {
  return kind == TimelineCellKind.reasoning ||
      kind == TimelineCellKind.toolCall ||
      kind == TimelineCellKind.systemNotice;
}

TimelineCellStatus? _statusFromString(String? status) {
  return switch (status) {
    'inProgress' || 'in_progress' => TimelineCellStatus.inProgress,
    'completed' => TimelineCellStatus.completed,
    'failed' => TimelineCellStatus.failed,
    'declined' => TimelineCellStatus.declined,
    'interrupted' => TimelineCellStatus.declined,
    null => null,
    _ => TimelineCellStatus.info,
  };
}

String _itemTitle(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      final command = _asString(item['command']);
      return command == null || command.isEmpty
          ? 'Ran command'
          : 'Ran $command';
    case 'fileChange':
      return 'file change';
    case 'mcpToolCall':
      final server = _asString(item['server']) ?? 'mcp';
      final tool = _asString(item['tool']) ?? 'tool';
      return '$server:$tool';
    case 'webSearch':
      return _asString(item['query']) ?? 'web search';
    case 'reasoning':
      return 'Thinking';
    case 'plan':
      return 'plan';
    default:
      return itemType;
  }
}

String? _itemSubtitle(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      return _asString(item['cwd']);
    case 'fileChange':
      return _changesSubtitle(item['changes']);
    case 'webSearch':
      return _asString(item['action']);
    default:
      return null;
  }
}

String? _itemDetails(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      return _asString(item['aggregatedOutput']) ?? _asString(item['output']);
    case 'fileChange':
      return _encodeIfNotEmpty(item['changes']);
    case 'mcpToolCall':
      return _asString(item['result']) ?? _encode(item['result']);
    case 'webSearch':
      return _encode(item);
    case 'reasoning':
      return _reasoningSummary(item);
    case 'plan':
      return _asString(item['text']);
    default:
      return _encode(item);
  }
}

String _assistantFinalText(Map<String, dynamic> item) {
  final plain = _asString(item['text']);
  if (plain != null && plain.isNotEmpty) {
    return plain;
  }

  final content = item['content'];
  if (content is List) {
    final buffer = StringBuffer();
    for (final entry in content) {
      if (entry is Map) {
        final map = _asMap(entry);
        if (_asString(map['type']) == 'text') {
          final text = _asString(map['text']);
          if (text != null) {
            if (buffer.isNotEmpty) {
              buffer.writeln();
            }
            buffer.write(text);
          }
        }
      }
    }
    return buffer.toString();
  }

  return '';
}

String _mergeFinalText(String current, String finalText) {
  if (finalText.isEmpty) {
    return current;
  }
  if (current.isEmpty) {
    return finalText;
  }
  if (current == finalText) {
    return current;
  }
  if (finalText.startsWith(current)) {
    return finalText;
  }
  return finalText;
}

String? _mergeOptionalText(String? current, String? next) {
  if (next == null || next.isEmpty) {
    return current;
  }
  if (current == null || current.isEmpty) {
    return next;
  }
  if (current == next) {
    return current;
  }
  if (next.startsWith(current)) {
    return next;
  }
  return next;
}

String _separatorTitle(Map<String, dynamic> turn) {
  final status = _asString(turn['status']) ?? 'completed';
  return 'turn $status';
}

String? _separatorSubtitle(Map<String, dynamic> turn) {
  final segments = <String>[];

  final durationMs = _extractDurationMs(turn);
  if (durationMs != null && durationMs > 0) {
    segments.add(_formatDuration(durationMs));
  }

  final totalTokens = _extractTotalTokens(turn);
  if (totalTokens != null && totalTokens > 0) {
    segments.add('$totalTokens tokens');
  }

  if (segments.isEmpty) {
    return null;
  }
  return segments.join(' • ');
}

int? _extractDurationMs(Map<String, dynamic> turn) {
  final durationMs =
      _asInt(turn['durationMs']) ??
      _asInt(turn['duration_ms']) ??
      _asInt(turn['computedDurationMs']) ??
      _asInt(turn['computed_duration_ms']) ??
      _asInt(turn['elapsedMs']) ??
      _asInt(turn['elapsed_ms']);
  if (durationMs != null) {
    return durationMs;
  }

  final startRaw =
      _asInt(turn['startedAt']) ??
      _asInt(turn['started_at']) ??
      _asInt(turn['createdAt']) ??
      _asInt(turn['created_at']);
  final endRaw =
      _asInt(turn['completedAt']) ??
      _asInt(turn['completed_at']) ??
      _asInt(turn['updatedAt']) ??
      _asInt(turn['updated_at']);
  if (startRaw == null || endRaw == null) {
    return null;
  }

  final startMs = _normalizeEpochToMs(startRaw);
  final endMs = _normalizeEpochToMs(endRaw);
  if (endMs < startMs) {
    return null;
  }
  return endMs - startMs;
}

int? _extractTotalTokens(Map<String, dynamic> turn) {
  final usage = _asMap(turn['usage']);
  final tokenUsage = _asMap(turn['tokenUsage']);
  final totalTokens =
      _asInt(usage['totalTokens']) ??
      _asInt(usage['total_tokens']) ??
      _asInt(tokenUsage['totalTokens']) ??
      _asInt(tokenUsage['total_tokens']) ??
      _asInt(turn['totalTokens']) ??
      _asInt(turn['total_tokens']);
  return totalTokens;
}

String _formatDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).round();
  if (totalSeconds <= 0) {
    return '0s';
  }
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (days > 0) {
    if (hours > 0) {
      return '${days}d ${hours}h';
    }
    if (minutes > 0) {
      return '${days}d ${minutes}m';
    }
    return '${days}d';
  }
  if (hours > 0) {
    if (minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${hours}h';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

int _normalizeEpochToMs(int raw) {
  // < 10^11 is likely epoch seconds, otherwise milliseconds.
  return raw < 100000000000 ? raw * 1000 : raw;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

String? _asString(dynamic value) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _changesSubtitle(dynamic rawChanges) {
  if (rawChanges is List) {
    final count = rawChanges.length;
    return '$count ${count == 1 ? 'change' : 'changes'}';
  }
  return null;
}

String _reasoningSummary(Map<String, dynamic> item) {
  final summary = item['summary'];
  if (summary is List) {
    return summary.map((entry) => entry.toString()).join('\n');
  }
  final summaryText = _asString(summary);
  if (summaryText != null && summaryText.isNotEmpty) {
    return summaryText;
  }

  final text = _asString(item['text']);
  return text ?? '';
}

String? _encodeIfNotEmpty(dynamic value) {
  if (value is List && value.isEmpty) {
    return null;
  }
  if (value is Map && value.isEmpty) {
    return null;
  }
  return _encode(value);
}

String? _encode(dynamic value) {
  if (value == null) {
    return null;
  }
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

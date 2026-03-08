import 'dart:convert';

import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/shared/utils/cast_utils.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/streaming/adaptive_chunking_policy.dart';
import 'package:alera/src/features/session/application/streaming/commit_tick_engine.dart';
import 'package:alera/src/features/session/application/streaming/markdown_stream_collector.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/collab_agent.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/token_usage.dart';

SessionState appendOptimisticUserMessage(
  SessionState state, {
  required String text,
  List<ComposerAttachment> attachments = const <ComposerAttachment>[],
  List<ComposerDraftItem> draftItems = const <ComposerDraftItem>[],
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final attachmentMaps = attachments
      .map(
        (a) => <String, dynamic>{
          'kind': a.kind.name,
          'path': a.path,
          'displayName': a.displayName,
          'mimeType': a.mimeType,
        },
      )
      .toList(growable: false);
  final cell = TimelineCell(
    id: 'user-${timestamp.microsecondsSinceEpoch}',
    turnId: null,
    kind: TimelineCellKind.userMessage,
    status: TimelineCellStatus.completed,
    createdAt: timestamp,
    updatedAt: timestamp,
    markdownText: text,
    metadata: <String, dynamic>{
      if (attachmentMaps.isNotEmpty) 'attachments': attachmentMaps,
      if (draftItems.isNotEmpty)
        'draftItems': draftItems
            .map(
              (item) => <String, dynamic>{
                'kind': item.kind.name,
                'name': item.name,
                'path': item.path,
                'tokenText': item.tokenText,
              },
            )
            .toList(growable: false),
    },
  );

  return state.copyWith(
    timelineCells: <TimelineCell>[...state.timelineCells, cell],
  );
}

SessionState appendQuestionAnswerCell(
  SessionState state, {
  required List<Map<String, String>> questionAnswers,
  String? turnId,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  final cell = TimelineCell(
    id: 'qa-${timestamp.microsecondsSinceEpoch}',
    turnId: turnId,
    kind: TimelineCellKind.questionAnswer,
    status: TimelineCellStatus.completed,
    createdAt: timestamp,
    updatedAt: timestamp,
    title: 'Asked ${questionAnswers.length} question${questionAnswers.length == 1 ? '' : 's'}',
    metadata: <String, dynamic>{
      'questions': questionAnswers,
    },
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
  final params = asMap(event.payload['params']);
  final next = _appendRawLog(state, event);

  switch (event.method) {
    case 'codex/event/item_started':
      return _onLegacyItemStarted(next, params, timestamp);
    case 'codex/event/item_completed':
      return _onLegacyItemCompleted(next, params, timestamp);
    case 'codex/event/task_complete':
      return _onLegacyTaskComplete(next, params, timestamp);
    case 'turn/started':
      return _onTurnStarted(next, params, timestamp);
    case 'turn/completed':
      return _onTurnCompleted(next, params, timestamp);
    case 'turn/failed':
      return _onTurnCompleted(next, params, timestamp);
    case 'item/started':
      return _onItemStarted(next, params, timestamp);
    case 'item/completed':
      return _onItemCompleted(next, params, timestamp);
    case 'item/agentMessage/delta':
      return _onAssistantDelta(next, params, timestamp);
    case 'item/reasoning/summaryTextDelta':
      return _onReasoningStatusDelta(next, params, timestamp);
    case 'item/reasoning/textDelta':
      return _onReasoningStatusDelta(next, params, timestamp);
    case 'item/commandExecution/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'Ran command',
      );
    case 'item/commandExecution/terminalInteraction':
      return _onTerminalInteraction(next, params, timestamp: timestamp);
    case 'item/fileChange/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'Edited files',
      );
    case 'item/mcpToolCall/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'MCP tool call',
      );
    case 'item/mcpToolCall/progress':
      return _onToolInteraction(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'MCP tool call',
      );
    case 'item/webSearch/outputDelta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'Web search',
      );
    case 'turn/diff/updated':
      return _onTurnDiffUpdated(next, params, timestamp);
    case 'item/plan/delta':
      return _onToolOutputDelta(
        next,
        params,
        timestamp: timestamp,
        fallbackTitle: 'plan',
      );
    case 'item/subAgent/started':
      return _onSubAgentStarted(next, params, timestamp);
    case 'item/subAgent/delta':
      return _onSubAgentDelta(next, params, timestamp);
    case 'item/subAgent/completed':
      return _onSubAgentCompleted(next, params, timestamp);
    case 'thread/tokenUsage/updated':
      return _onThreadTokenUsageUpdated(next, params);
    case 'account/rateLimits/updated':
      return _onAccountRateLimitsUpdated(next, params);
    case 'codex/event/token_count':
      return _onTokenCount(next, asMap(params['msg']));
    case 'token_count':
      return _onTokenCount(next, params);
    case 'error':
    case 'stream/error':
    case 'stream_error':
      return _onStreamError(next, params);
    case 'background/event':
      return _onBackgroundStatus(next, params);
    // Multi-agent (collab) events:
    case 'codex/event/collab_agent_spawn_begin':
    case 'codex/event/collab_agent_spawn_end':
    case 'codex/event/collab_agent_interaction_begin':
    case 'codex/event/collab_agent_interaction_end':
    case 'codex/event/collab_waiting_begin':
    case 'codex/event/collab_waiting_end':
    case 'codex/event/collab_close_begin':
    case 'codex/event/collab_close_end':
    case 'codex/event/collab_resume_begin':
    case 'codex/event/collab_resume_end':
      return _onCollabEvent(next, event.method, asMap(params['msg']));
    default:
      return next;
  }
}

SessionState reduceCommitTick(
  SessionState state, {
  CommitTickScope scope = CommitTickScope.anyMode,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  var nextState = state;
  final activePhase = _normalizeAgentPhase(nextState.activeAgentStreamPhase);
  final canSoftFlushFinalAnswer =
      nextState.activeAgentStreamItemId != null &&
      nextState.activeAgentStreamTurnId != null &&
      activePhase == 'final_answer';
  if (canSoftFlushFinalAnswer) {
    final softFlush = maybeFlushSoftChunk(
      nextState.streamCollector,
      now: timestamp,
    );
    if (softFlush.chunk != null && softFlush.chunk!.trim().isNotEmpty) {
      final queued = <StreamQueuedLine>[
        ...nextState.streamQueue,
        StreamQueuedLine(
          turnId: nextState.activeAgentStreamTurnId!,
          itemId: nextState.activeAgentStreamItemId,
          streamPhase: activePhase,
          text: softFlush.chunk!,
          enqueuedAt: timestamp,
          isSoftChunk: true,
          appendWithoutNewline: true,
        ),
      ];
      nextState = nextState.copyWith(
        streamCollector: softFlush.state,
        streamQueue: queued,
        streamQueueDepth: queued.length,
        streamOldestAgeMs: 0,
      );
    } else if (!identical(softFlush.state, nextState.streamCollector)) {
      nextState = nextState.copyWith(streamCollector: softFlush.state);
    }
  }

  final result = runCommitTick(
    policy: nextState.chunkingPolicy,
    queue: nextState.streamQueue,
    scope: scope,
    now: timestamp,
  );

  var next = nextState.copyWith(
    chunkingPolicy: result.policy,
    streamQueue: result.remainingQueue,
    streamQueueDepth: result.queueDepth,
    streamOldestAgeMs: result.oldestAgeMs,
    clearStreamOldestAgeMs: result.oldestAgeMs == null,
  );

  if (result.drainedLines.isNotEmpty) {
    final cells = <TimelineCell>[...next.timelineCells];
    var activeStreamingAssistantCellId = next.activeStreamingAssistantCellId;
    var activeTurnId = next.activeTurnId;
    var turnHadWorkActivity = next.turnHadWorkActivity;

    for (final line in result.drainedLines) {
      final text = line.appendWithoutNewline
          ? line.text
          : line.text.trimRight();
      final streamPhase = _normalizeAgentPhase(line.streamPhase);
      if (streamPhase == 'final_answer') {
        final assistantCellId = line.itemId ?? 'assistant-final-${line.turnId}';
        final assistantIndex = cells.findIndexById(assistantCellId);
        if (assistantIndex == -1) {
          cells.add(
            TimelineCell(
              id: assistantCellId,
              turnId: line.turnId,
              itemId: line.itemId,
              kind: TimelineCellKind.assistantMessage,
              status: TimelineCellStatus.inProgress,
              createdAt: timestamp,
              updatedAt: timestamp,
              isStreaming: true,
              markdownText: text,
              metadata: _withStreamCommitMetadata(
                const <String, dynamic>{},
                itemId: line.itemId,
                streamPhase: streamPhase,
              ),
            ),
          );
        } else {
          final existing = cells[assistantIndex];
          final currentText = existing.markdownText ?? '';
          final String nextText;
          if (text.isEmpty) {
            // Empty line = paragraph break
            nextText = currentText.isEmpty ? '' : '$currentText\n\n';
          } else {
            nextText = currentText.isEmpty
                ? text
                : line.appendWithoutNewline
                    ? '$currentText$text'
                    : '$currentText\n$text';
          }
          cells[assistantIndex] = existing.copyWith(
            turnId: line.turnId,
            itemId: line.itemId,
            status: TimelineCellStatus.inProgress,
            isStreaming: true,
            markdownText: nextText,
            metadata: _withStreamCommitMetadata(
              existing.metadata,
              itemId: line.itemId,
              streamPhase: streamPhase,
            ),
            updatedAt: timestamp,
          );
        }
        activeStreamingAssistantCellId = assistantCellId;
      } else if (text.isNotEmpty) {
        cells.add(
          TimelineCell(
            id: 'stream-${line.turnId}-${timestamp.microsecondsSinceEpoch}',
            turnId: line.turnId,
            itemId: line.itemId,
            kind: TimelineCellKind.progressText,
            status: TimelineCellStatus.completed,
            createdAt: timestamp,
            updatedAt: timestamp,
            markdownText: text,
            metadata: <String, dynamic>{
              'isInterim': true,
              'streamSource': 'commit_tick',
              if (line.itemId != null) 'streamItemId': line.itemId,
              'streamCommitted': true,
              'streamPhase': streamPhase,
              'isWorkActivity': true,
            },
          ),
        );
        turnHadWorkActivity = true;
      }
      activeTurnId = line.turnId;
    }
    next = next.copyWith(
      timelineCells: cells,
      activeStreamingAssistantCellId: activeStreamingAssistantCellId,
      activeTurnId: activeTurnId,
      turnHadWorkActivity: turnHadWorkActivity,
    );
  }

  if (next.pendingStatusRestore && result.allIdle) {
    next = next.copyWith(
      pendingStatusRestore: false,
      statusHeader: next.activeTurnId == null ? null : 'Working',
    );
  }

  return next;
}

SessionState _appendRawLog(SessionState state, SessionNotificationEvent event) {
  final text = '${event.method}: ${event.payload['params'] ?? ''}';
  final nextLog = <String>[...state.activityLog, text];
  final clipped = nextLog.length <= 200
      ? nextLog
      : nextLog.sublist(nextLog.length - 200);
  return state.copyWith(activityLog: clipped);
}

SessionState _onLegacyItemStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final msg = asMap(params['msg']);
  if ((_asString(msg['type']) ?? '').toLowerCase() != 'item_started') {
    return state;
  }

  final item = asMap(msg['item']);
  final itemType = _normalizeLegacyItemType(_asString(item['type']));
  if (itemType != 'agentMessage') {
    return state;
  }

  final itemId = _asString(item['id']);
  final turnId = _asString(msg['turn_id']);
  if (itemId == null || itemId.isEmpty || turnId == null || turnId.isEmpty) {
    return state;
  }

  final previousPhase = state.agentMessagePhaseByItemId[itemId];
  final phase = _mergeAgentPhase(
    previousPhase: previousPhase,
    incomingPhase: _normalizeAgentPhase(_asString(item['phase'])),
  );
  final nextByItem = <String, String>{...state.agentMessagePhaseByItemId};
  nextByItem[itemId] = phase;

  final nextFinalByTurn = <String, String>{...state.finalAnswerItemIdByTurn};
  if (phase == 'final_answer') {
    nextFinalByTurn[turnId] = itemId;
  }

  var nextState = state.copyWith(
    agentMessagePhaseByItemId: nextByItem,
    finalAnswerItemIdByTurn: nextFinalByTurn,
  );
  if (phase == 'final_answer') {
    nextState = _reclassifyUnknownAssistantCellsForTurn(
      nextState,
      turnId: turnId,
      finalItemId: itemId,
      timestamp: timestamp,
    );
  }
  return nextState;
}

SessionState _onLegacyItemCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final msg = asMap(params['msg']);
  if ((_asString(msg['type']) ?? '').toLowerCase() != 'item_completed') {
    return state;
  }

  final item = asMap(msg['item']);
  final itemType = _normalizeLegacyItemType(_asString(item['type']));
  if (itemType != 'agentMessage') {
    return state;
  }

  final itemId = _asString(item['id']);
  final turnId = _asString(msg['turn_id']);
  if (itemId == null || itemId.isEmpty || turnId == null || turnId.isEmpty) {
    return state;
  }

  final previousPhase = state.agentMessagePhaseByItemId[itemId];
  final phase = _mergeAgentPhase(
    previousPhase: previousPhase,
    incomingPhase: _normalizeAgentPhase(_asString(item['phase'])),
  );
  final nextByItem = <String, String>{...state.agentMessagePhaseByItemId};
  nextByItem[itemId] = phase;

  final nextFinalByTurn = <String, String>{...state.finalAnswerItemIdByTurn};
  if (phase == 'final_answer') {
    nextFinalByTurn[turnId] = itemId;
  }

  var nextState = state.copyWith(
    agentMessagePhaseByItemId: nextByItem,
    finalAnswerItemIdByTurn: nextFinalByTurn,
  );
  if (phase == 'final_answer') {
    nextState = _reclassifyUnknownAssistantCellsForTurn(
      nextState,
      turnId: turnId,
      finalItemId: itemId,
      timestamp: timestamp,
    );
  }
  final normalizedItem = _normalizeLegacyAssistantCompletionItem(
    item,
    phase: phase,
  );
  return _onAssistantItemCompleted(
    nextState,
    turnId: turnId,
    itemId: itemId,
    item: normalizedItem,
    timestamp: timestamp,
  );
}

SessionState _onLegacyTaskComplete(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final msg = asMap(params['msg']);
  if ((_asString(msg['type']) ?? '').toLowerCase() != 'task_complete') {
    return state;
  }

  final turnId = _asString(msg['turn_id']) ?? state.activeTurnId;
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  final hasExplicitFinal = state.finalAnswerItemIdByTurn.containsKey(turnId);
  final hasActiveStreamForTurn = state.activeAgentStreamTurnId == turnId;
  final hasStreamingAssistantForTurn = state.timelineCells.any(
    (cell) =>
        cell.turnId == turnId &&
        cell.kind == TimelineCellKind.assistantMessage &&
        cell.isStreaming,
  );
  if (hasExplicitFinal &&
      !hasActiveStreamForTurn &&
      !hasStreamingAssistantForTurn) {
    return state;
  }

  final lastAgentMessage = _asString(msg['last_agent_message'])?.trim();
  if (lastAgentMessage == null || lastAgentMessage.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  TimelineCell? existingAssistant;
  for (var i = cells.length - 1; i >= 0; i--) {
    final candidate = cells[i];
    if (candidate.turnId == turnId &&
        candidate.kind == TimelineCellKind.assistantMessage) {
      existingAssistant = candidate;
      break;
    }
  }

  final cellId = existingAssistant?.id ?? 'assistant-final-$turnId';
  final existingIndex = existingAssistant == null
      ? -1
      : cells.findIndexById(existingAssistant.id);

  final metadata = <String, dynamic>{
    'streamPhase': 'final_answer',
    'source': 'task_complete',
  };

  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: _asString(state.finalAnswerItemIdByTurn[turnId]),
        kind: TimelineCellKind.assistantMessage,
        status: TimelineCellStatus.completed,
        createdAt: timestamp,
        updatedAt: timestamp,
        markdownText: lastAgentMessage,
        metadata: metadata,
      ),
    );
  } else {
    cells[existingIndex] = cells[existingIndex].copyWith(
      markdownText: lastAgentMessage,
      isStreaming: false,
      status: TimelineCellStatus.completed,
      metadata: metadata,
      updatedAt: timestamp,
    );
  }

  final shouldClearActiveStream = state.activeAgentStreamTurnId == turnId;
  final shouldClearStreamingAssistant =
      shouldClearActiveStream &&
      (state.activeStreamingAssistantCellId ?? '').isNotEmpty;
  return state.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: shouldClearStreamingAssistant,
    clearActiveAgentStreamItemId: shouldClearActiveStream,
    clearActiveAgentStreamTurnId: shouldClearActiveStream,
    clearActiveAgentStreamPhase: shouldClearActiveStream,
    clearActiveAgentStreamLastDeltaAtMs: shouldClearActiveStream,
  );
}

Map<String, dynamic> _withStreamCommitMetadata(
  Map<String, dynamic> current, {
  required String? itemId,
  required String streamPhase,
}) {
  return <String, dynamic>{
    ...current,
    'streamSource': 'commit_tick',
    if (itemId != null && itemId.isNotEmpty) 'streamItemId': itemId,
    'streamCommitted': true,
    'streamPhase': streamPhase,
  };
}

SessionState _flushActiveAgentStreamToQueue(SessionState state, DateTime now) {
  final itemId = state.activeAgentStreamItemId;
  final turnId = state.activeAgentStreamTurnId;
  if (itemId == null ||
      itemId.isEmpty ||
      turnId == null ||
      turnId.isEmpty ||
      state.streamCollector.pendingBuffer.isEmpty) {
    return state.copyWith(
      streamCollector: const MarkdownStreamCollectorState(),
    );
  }

  final finalize = finalizeMarkdownStream(state.streamCollector);
  if (finalize.completedLines.isEmpty) {
    return state.copyWith(streamCollector: finalize.state);
  }

  final streamPhase = _normalizeAgentPhase(state.activeAgentStreamPhase);
  final queued = <StreamQueuedLine>[
    ...state.streamQueue,
    ...finalize.completedLines.map(
      (line) => StreamQueuedLine(
        turnId: turnId,
        itemId: itemId,
        streamPhase: streamPhase,
        text: line,
        enqueuedAt: now,
      ),
    ),
  ];

  return state.copyWith(
    streamCollector: finalize.state,
    streamQueue: queued,
    streamQueueDepth: queued.length,
    streamOldestAgeMs: 0,
  );
}

String _resolveAgentPhase(
  SessionState state, {
  required String itemId,
  required String turnId,
  required Map<String, dynamic> item,
}) {
  final explicit = _normalizeAgentPhase(_asString(item['phase']));
  if (explicit != 'unknown') {
    return explicit;
  }

  final fromMap = _normalizeAgentPhase(state.agentMessagePhaseByItemId[itemId]);
  if (fromMap != 'unknown') {
    return fromMap;
  }

  final finalForTurn = state.finalAnswerItemIdByTurn[turnId];
  if (finalForTurn != null && finalForTurn.isNotEmpty) {
    return finalForTurn == itemId ? 'final_answer' : 'commentary';
  }

  // Smart fallback for providers that omit phase:
  // treat as final by default unless an explicit final for this turn is known.
  return 'final_answer';
}

String _mergeAgentPhase({
  required String? previousPhase,
  required String incomingPhase,
}) {
  final normalizedPrevious = _normalizeAgentPhase(previousPhase);
  if (incomingPhase == 'unknown' && normalizedPrevious != 'unknown') {
    return normalizedPrevious;
  }
  return incomingPhase;
}

SessionState _reclassifyUnknownAssistantCellsForTurn(
  SessionState state, {
  required String turnId,
  required String finalItemId,
  required DateTime timestamp,
}) {
  final cells = <TimelineCell>[...state.timelineCells];
  var mutated = false;
  var clearActiveStreaming = false;

  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell.turnId != turnId ||
        cell.kind != TimelineCellKind.assistantMessage) {
      continue;
    }
    final itemId = cell.itemId;
    if (itemId == null || itemId.isEmpty || itemId == finalItemId) {
      continue;
    }
    final phase = _normalizeAgentPhase(state.agentMessagePhaseByItemId[itemId]);
    if (phase != 'unknown') {
      continue;
    }

    final text = (cell.markdownText ?? '').trim();
    if (text.isEmpty) {
      if (state.activeStreamingAssistantCellId == cell.id) {
        clearActiveStreaming = true;
      }
      cells.removeAt(i);
      i -= 1;
      mutated = true;
      continue;
    }

    final metadata = <String, dynamic>{
      ...cell.metadata,
      'isInterim': true,
      'streamSource': 'phase_reclassification',
      'streamItemId': itemId,
      'streamCommitted': true,
      'streamPhase': 'commentary',
      'isWorkActivity': true,
    };

    if (state.activeStreamingAssistantCellId == cell.id) {
      clearActiveStreaming = true;
    }

    cells[i] = cell.copyWith(
      kind: TimelineCellKind.progressText,
      status: TimelineCellStatus.completed,
      isStreaming: false,
      metadata: metadata,
      updatedAt: timestamp,
    );
    mutated = true;
  }

  if (!mutated) {
    return state;
  }
  return state.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: clearActiveStreaming,
    turnHadWorkActivity: true,
  );
}

String _normalizeAgentPhase(String? raw) {
  final normalized = (raw ?? '').toLowerCase().trim();
  if (normalized == 'final_answer' || normalized == 'finalanswer') {
    return 'final_answer';
  }
  if (normalized == 'commentary') {
    return 'commentary';
  }
  return 'unknown';
}

String _normalizeLegacyItemType(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  if (value == 'agentmessage' || value == 'agent_message') {
    return 'agentMessage';
  }
  if (value == 'usermessage' || value == 'user_message') {
    return 'userMessage';
  }
  if (value == 'commandexecution' || value == 'command_execution') {
    return 'commandExecution';
  }
  if (value == 'filechange' || value == 'file_change') {
    return 'fileChange';
  }
  if (value == 'mcptoolcall' || value == 'mcp_tool_call') {
    return 'mcpToolCall';
  }
  if (value == 'websearch' || value == 'web_search') {
    return 'webSearch';
  }
  if (value == 'reasoning') {
    return 'reasoning';
  }
  return raw ?? '';
}

void _trimTrailingOverlapWorkedVsFinal(
  List<TimelineCell> cells, {
  required String turnId,
}) {
  var finalIndex = -1;
  var finalText = '';
  for (var i = cells.length - 1; i >= 0; i--) {
    final candidate = cells[i];
    if (candidate.turnId != turnId ||
        candidate.kind != TimelineCellKind.assistantMessage) {
      continue;
    }
    final text = (candidate.markdownText ?? '').trim();
    if (text.isEmpty) {
      continue;
    }
    finalIndex = i;
    finalText = text;
    break;
  }
  if (finalIndex == -1 || finalText.isEmpty) {
    return;
  }

  var lastProgressIndex = -1;
  for (var i = cells.length - 1; i >= 0; i--) {
    final candidate = cells[i];
    if (candidate.turnId != turnId ||
        candidate.kind != TimelineCellKind.progressText) {
      continue;
    }
    final text = candidate.markdownText ?? '';
    if (text.trim().isEmpty) {
      continue;
    }
    lastProgressIndex = i;
    break;
  }
  if (lastProgressIndex == -1) {
    return;
  }

  final progress = cells[lastProgressIndex];
  final progressText = progress.markdownText ?? '';
  final overlap = _trailingLeadingOverlapLength(progressText, finalText);
  if (overlap <= 0) {
    return;
  }
  final trimmedProgressText = progressText.trimRight();
  final isFullDuplicate = overlap >= trimmedProgressText.length;
  final isMeaningfulOverlap = overlap >= 8;
  if (!isFullDuplicate && !isMeaningfulOverlap) {
    return;
  }

  final trimmedProgress = progressText
      .substring(0, progressText.length - overlap)
      .trimRight();
  if (trimmedProgress.isEmpty) {
    cells.removeAt(lastProgressIndex);
    return;
  }

  cells[lastProgressIndex] = progress.copyWith(
    markdownText: trimmedProgress,
    updatedAt: cells[finalIndex].updatedAt,
  );
}

int _trailingLeadingOverlapLength(String left, String right) {
  final max = left.length < right.length ? left.length : right.length;
  for (var len = max; len > 0; len--) {
    final leftSlice = left.substring(left.length - len);
    final rightSlice = right.substring(0, len);
    if (leftSlice == rightSlice) {
      return len;
    }
  }
  return 0;
}

SessionState _onTurnStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turn = asMap(params['turn']);
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
    final userIndex = cells.findIndexById(pendingUserCellId);
    if (userIndex != -1) {
      final wasSteering =
          cells[userIndex].metadata[TimelineCellMetadata.isSteeringKey] == true;
      cells[userIndex] = cells[userIndex].copyWith(
        turnId: turnId,
        updatedAt: timestamp,
        status: wasSteering ? TimelineCellStatus.completed : null,
      );
    }
  }

  final nextFinalByTurn = <String, String>{...state.finalAnswerItemIdByTurn};
  nextFinalByTurn.remove(turnId);

  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    statusHeader: 'Working',
    pendingStatusRestore: false,
    streamCollector: const MarkdownStreamCollectorState(),
    streamQueue: const <StreamQueuedLine>[],
    chunkingPolicy: const AdaptiveChunkingPolicyState(),
    streamQueueDepth: 0,
    clearStreamOldestAgeMs: true,
    clearActiveAgentStreamItemId: true,
    clearActiveAgentStreamTurnId: true,
    clearActiveAgentStreamPhase: true,
    clearActiveAgentStreamLastDeltaAtMs: true,
    finalAnswerItemIdByTurn: nextFinalByTurn,
    turnHadWorkActivity: false,
    turnRuntimeMetrics: const <String, dynamic>{},
    reasoningBufferByItemId: const <String, String>{},
    clearActiveExecCellId: true,
    clearActivePlanCellId: true,
  );
}

SessionState _onTurnCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turn = asMap(params['turn']);
  final turnId = _asString(turn['id']);
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  var nextState = state;
  if (nextState.activeAgentStreamItemId != null &&
      nextState.activeAgentStreamTurnId == turnId) {
    nextState = _flushActiveAgentStreamToQueue(nextState, timestamp);
  }

  var guard = 0;
  while (nextState.streamQueue.isNotEmpty && guard < 200) {
    nextState = reduceCommitTick(
      nextState,
      scope: CommitTickScope.anyMode,
      now: timestamp,
    );
    guard += 1;
  }

  final cells = <TimelineCell>[...nextState.timelineCells];
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    // Safety net: complete any orphaned steering cells still in-progress.
    if (cell.kind == TimelineCellKind.userMessage &&
        cell.status == TimelineCellStatus.inProgress &&
        cell.metadata[TimelineCellMetadata.isSteeringKey] == true) {
      cells[i] = cell.copyWith(
        status: TimelineCellStatus.completed,
        turnId: cell.turnId ?? turnId,
        updatedAt: timestamp,
      );
      continue;
    }
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
    if (cell.kind == TimelineCellKind.progressText &&
        cell.status == TimelineCellStatus.inProgress) {
      cells[i] = cell.copyWith(
        status: TimelineCellStatus.completed,
        updatedAt: timestamp,
      );
      continue;
    }
    if (_isSecondaryKind(cell.kind)) {
      cells[i] = cell.copyWith(isCollapsed: true, updatedAt: timestamp);
    }
  }

  final runtimeMetrics = <String, dynamic>{...nextState.turnRuntimeMetrics};
  final showWorkSeparator =
      nextState.turnHadWorkActivity || runtimeMetrics.isNotEmpty;

  if (!showWorkSeparator) {
    cells.removeWhere(
      (cell) =>
          cell.turnId == turnId && cell.kind == TimelineCellKind.progressText,
    );
  }

  final durationFromCells = _computeTurnDurationFromCells(
    cells,
    turnId: turnId,
    turnCompletedAt: timestamp,
  );
  final separatorId = 'turn-separator-$turnId';
  final separatorMetadata = <String, dynamic>{
    ...turn,
    'isWorkActivity': nextState.turnHadWorkActivity,
    if (runtimeMetrics.isNotEmpty) 'runtimeMetrics': runtimeMetrics,
  };
  if (durationFromCells != null && durationFromCells > 0) {
    separatorMetadata['computedDurationMs'] = durationFromCells;
  }
  final existingSeparatorIndex = cells.findIndexById(separatorId);
  if (showWorkSeparator) {
    final separator = TimelineCell(
      id: separatorId,
      turnId: turnId,
      kind: TimelineCellKind.turnSeparator,
      status:
          _statusFromString(_asString(turn['status'])) ??
          TimelineCellStatus.info,
      createdAt: timestamp,
      updatedAt: timestamp,
      title: _separatorTitle(turn),
      subtitle: _separatorSubtitle(separatorMetadata),
      metadata: separatorMetadata,
    );
    if (existingSeparatorIndex == -1) {
      cells.add(separator);
    } else {
      cells[existingSeparatorIndex] = separator;
    }
  } else {
    if (existingSeparatorIndex != -1) {
      cells.removeAt(existingSeparatorIndex);
    }
  }

  final turnStatus = (_asString(turn['status']) ?? '').toLowerCase();
  if (turnStatus == 'interrupted' && state.isInterrupting) {
    final hasUserStopNotice = cells.any(
      (cell) =>
          cell.turnId == turnId &&
          cell.kind == TimelineCellKind.systemNotice &&
          _asString(cell.metadata['noticeType']) == 'user_stop',
    );
    if (!hasUserStopNotice) {
      cells.add(
        TimelineCell(
          id: 'notice-user-stop-$turnId',
          turnId: turnId,
          kind: TimelineCellKind.systemNotice,
          status: TimelineCellStatus.info,
          createdAt: timestamp,
          updatedAt: timestamp,
          // Display-only timeline event. This must never be sent as model input.
          markdownText: 'Stopped by user',
          metadata: const <String, dynamic>{
            'noticeType': 'user_stop',
            TimelineCellMetadata.uiPlacementKey:
                TimelineCellMetadata.outsideWorked,
            'ephemeralInputOnly': true,
          },
        ),
      );
    }
  }

  _trimTrailingOverlapWorkedVsFinal(cells, turnId: turnId);

  var clearStreaming = false;
  final activeStreamingId = nextState.activeStreamingAssistantCellId;
  if (activeStreamingId != null) {
    final activeIndex = cells.findIndexById(activeStreamingId);
    if (activeIndex != -1 && cells[activeIndex].turnId == turnId) {
      clearStreaming = true;
    }
  }

  final nextFinalByTurn = <String, String>{
    ...nextState.finalAnswerItemIdByTurn,
  };
  nextFinalByTurn.remove(turnId);

  return nextState.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: clearStreaming,
    clearActiveTurnId: nextState.activeTurnId == turnId,
    clearStatusHeader: true,
    pendingStatusRestore: false,
    streamCollector: const MarkdownStreamCollectorState(),
    streamQueue: const <StreamQueuedLine>[],
    chunkingPolicy: const AdaptiveChunkingPolicyState(),
    streamQueueDepth: 0,
    clearStreamOldestAgeMs: true,
    clearActiveAgentStreamItemId: nextState.activeAgentStreamTurnId == turnId,
    clearActiveAgentStreamTurnId: nextState.activeAgentStreamTurnId == turnId,
    clearActiveAgentStreamPhase: nextState.activeAgentStreamTurnId == turnId,
    clearActiveAgentStreamLastDeltaAtMs:
        nextState.activeAgentStreamTurnId == turnId,
    finalAnswerItemIdByTurn: nextFinalByTurn,
    turnHadWorkActivity: false,
    turnRuntimeMetrics: const <String, dynamic>{},
    reasoningBufferByItemId: const <String, String>{},
    clearActiveExecCellId: true,
    clearActivePlanCellId: true,
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
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      delta.isEmpty) {
    return state;
  }

  var next = state;
  final activeItemId = next.activeAgentStreamItemId;
  final activeTurnId = next.activeAgentStreamTurnId;
  if (activeItemId != null &&
      activeTurnId != null &&
      (activeItemId != itemId || activeTurnId != turnId)) {
    next = _flushActiveAgentStreamToQueue(next, timestamp);
  }

  final phase = _resolveAgentPhase(
    next,
    itemId: itemId,
    turnId: turnId,
    item: const <String, dynamic>{},
  );
  final push = pushMarkdownDelta(next.streamCollector, delta, now: timestamp);
  var queued = next.streamQueue;
  if (push.completedLines.isNotEmpty) {
    queued = <StreamQueuedLine>[
      ...next.streamQueue,
      ...push.completedLines.map(
        (line) => StreamQueuedLine(
          turnId: turnId,
          itemId: itemId,
          streamPhase: phase,
          text: line,
          enqueuedAt: timestamp,
        ),
      ),
    ];
  }

  next = next.copyWith(
    streamCollector: push.state,
    streamQueue: queued,
    activeTurnId: turnId,
    activeAgentStreamItemId: itemId,
    activeAgentStreamTurnId: turnId,
    activeAgentStreamPhase: phase,
    activeAgentStreamLastDeltaAtMs: timestamp.millisecondsSinceEpoch,
    statusHeader: 'Working',
    pendingStatusRestore: false,
  );
  if (queued.isNotEmpty) {
    next = reduceCommitTick(
      next,
      scope: CommitTickScope.anyMode,
      now: timestamp,
    );
  }
  return next.copyWith(
    streamQueueDepth: next.streamQueue.length,
    streamOldestAgeMs: next.streamQueue.isEmpty ? null : next.streamOldestAgeMs,
    clearStreamOldestAgeMs: next.streamQueue.isEmpty,
  );
}

SessionState _onReasoningStatusDelta(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId =
      _asString(params['itemId']) ??
      (turnId == null ? null : 'reasoning-$turnId');
  final delta =
      _asString(params['delta']) ??
      _asString(params['textDelta']) ??
      _asString(params['summaryTextDelta']) ??
      '';
  if (turnId == null || turnId.isEmpty || itemId == null || delta.isEmpty) {
    return state;
  }

  final sanitized = _sanitizeInterimDeltaForDisplay(delta);
  if (sanitized == null || sanitized.trim().isEmpty) {
    return state.copyWith(
      activeTurnId: turnId,
      statusHeader: 'Thinking',
      pendingStatusRestore: true,
    );
  }

  final nextReasoning = <String, String>{...state.reasoningBufferByItemId};
  final current = nextReasoning[itemId];
  nextReasoning[itemId] = current == null || current.isEmpty
      ? sanitized
      : '$current$sanitized';

  return state.copyWith(
    activeTurnId: turnId,
    reasoningBufferByItemId: nextReasoning,
    statusHeader: 'Thinking',
    pendingStatusRestore: true,
  );
}

SessionState _onTurnDiffUpdated(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final diff = _asString(params['diff']) ?? '';
  if (turnId == null || turnId.isEmpty || diff.isEmpty) {
    return state;
  }

  final metrics = <String, dynamic>{
    ...state.turnRuntimeMetrics,
    'diffChars': diff.length,
    'hasDiff': true,
    'lastDiffUpdatedAtMs': timestamp.millisecondsSinceEpoch,
  };
  return state.copyWith(
    activeTurnId: turnId,
    statusHeader: 'Editing files',
    pendingStatusRestore: true,
    turnHadWorkActivity: true,
    turnRuntimeMetrics: metrics,
    lastTurnDiff: diff,
  );
}

SessionState _onToolOutputDelta(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
  required String fallbackTitle,
}) {
  final delta = _asString(params['delta']) ?? '';
  return _onToolDetailsChunk(
    state,
    params,
    timestamp: timestamp,
    fallbackTitle: fallbackTitle,
    chunk: delta,
    append: true,
  );
}

SessionState _onToolInteraction(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
  required String fallbackTitle,
}) {
  final chunk =
      _asString(params['message']) ??
      _asString(params['stdin']) ??
      _asString(params['delta']) ??
      '';
  return _onToolDetailsChunk(
    state,
    params,
    timestamp: timestamp,
    fallbackTitle: fallbackTitle,
    chunk: chunk,
    append: true,
  );
}

SessionState _onTerminalInteraction(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
}) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final message =
      _asString(params['message']) ??
      _asString(params['stdin']) ??
      _asString(params['delta']) ??
      '';
  final lower = message.toLowerCase();
  final isWaitingBackground =
      lower.contains('background terminal') &&
      (lower.contains('wait') ||
          lower.contains('waiting') ||
          lower.contains('idle'));

  if (isWaitingBackground) {
    return state.copyWith(
      activeTurnId: turnId,
      statusHeader: 'Waiting for background terminal',
      pendingStatusRestore: false,
      turnHadWorkActivity: true,
    );
  }

  final next = _onToolInteraction(
    state,
    params,
    timestamp: timestamp,
    fallbackTitle: 'Ran command',
  );
  return next.copyWith(
    activeTurnId: turnId,
    statusHeader: 'Working',
    pendingStatusRestore: false,
    turnHadWorkActivity: true,
  );
}

SessionState _onTokenCount(SessionState state, Map<String, dynamic> params) {
  final info = asMap(params['info']);
  if (info.isEmpty) {
    return state;
  }
  final totalUsage = asMap(info['total_token_usage']).isNotEmpty
      ? asMap(info['total_token_usage'])
      : asMap(info['totalTokenUsage']);
  final nextMetrics = <String, dynamic>{...state.turnRuntimeMetrics};
  if (totalUsage.isNotEmpty) {
    nextMetrics['tokenUsage'] = totalUsage;
    final totalTokens =
        _asInt(totalUsage['total_tokens']) ?? _asInt(totalUsage['totalTokens']);
    if (totalTokens != null) {
      nextMetrics['totalTokens'] = totalTokens;
    }
  } else {
    nextMetrics['tokenInfo'] = info;
  }
  return state.copyWith(turnRuntimeMetrics: nextMetrics);
}

SessionState _onThreadTokenUsageUpdated(
  SessionState state,
  Map<String, dynamic> params,
) {
  final tokenUsage = asMap(params['tokenUsage']);
  if (tokenUsage.isEmpty) {
    return state;
  }

  final tokenUsageInfo = TokenUsageInfo.fromMap(<String, dynamic>{
    'totalTokenUsage': tokenUsage['total'],
    'lastTokenUsage': tokenUsage['last'],
    'modelContextWindow': tokenUsage['modelContextWindow'],
  });
  final nextMetrics = <String, dynamic>{...state.turnRuntimeMetrics};
  nextMetrics['tokenUsage'] = tokenUsage;
  nextMetrics['totalTokens'] = tokenUsageInfo.currentContextTokens;

  return state.copyWith(
    turnRuntimeMetrics: nextMetrics,
    contextUsage: state.contextUsage.copyWith(
      tokenUsageInfo: tokenUsageInfo,
      isCompacting: false,
    ),
  );
}

SessionState _onAccountRateLimitsUpdated(
  SessionState state,
  Map<String, dynamic> params,
) {
  final rateLimits = asMap(params['rateLimits']);
  if (rateLimits.isEmpty) {
    return state;
  }

  return state.copyWith(
    contextUsage: state.contextUsage.copyWith(
      rateLimits: RateLimitSnapshot.fromMap(rateLimits),
    ),
  );
}

// ---------------------------------------------------------------------------
// Multi-agent (collab) events
// ---------------------------------------------------------------------------

SessionState _onCollabEvent(
  SessionState state,
  String method,
  Map<String, dynamic> params,
) {
  switch (method) {
    case 'codex/event/collab_agent_spawn_begin':
      return _onCollabSpawnBegin(state, params);
    case 'codex/event/collab_agent_spawn_end':
      return _onCollabSpawnEnd(state, params);
    case 'codex/event/collab_agent_interaction_end':
      return _onCollabInteractionEnd(state, params);
    case 'codex/event/collab_waiting_end':
      return _onCollabWaitingEnd(state, params);
    case 'codex/event/collab_close_end':
      return _onCollabCloseEnd(state, params);
    case 'codex/event/collab_resume_end':
      return _onCollabResumeEnd(state, params);
    // Begin events for interaction/waiting/close/resume are informational
    // (no state change needed; UI can show from the begin event if desired
    // in the future).
    default:
      return state;
  }
}

SessionState _onCollabSpawnBegin(
  SessionState state,
  Map<String, dynamic> params,
) {
  final callId = _asString(params['call_id']) ?? '';
  if (callId.isEmpty) return state;

  final senderThreadId = _asString(params['sender_thread_id']) ?? '';
  final prompt = _asString(params['prompt']);

  final entry = CollabAgentEntry(
    callId: callId,
    ref: const CollabAgentRef(threadId: ''),
    status: CollabAgentStatus.pendingInit,
    prompt: prompt,
    senderThreadId: senderThreadId,
  );

  return state.copyWith(
    collabAgents: <CollabAgentEntry>[...state.collabAgents, entry],
  );
}

SessionState _onCollabSpawnEnd(
  SessionState state,
  Map<String, dynamic> params,
) {
  final callId = _asString(params['call_id']) ?? '';
  if (callId.isEmpty) return state;

  final newThreadId = _asString(params['new_thread_id']) ?? '';
  final nickname = _asString(params['new_agent_nickname']);
  final role = _asString(params['new_agent_role']);
  final status = parseAgentStatus(params['status']);
  final message = parseAgentStatusMessage(params['status']);

  final agents = <CollabAgentEntry>[...state.collabAgents];
  final index = agents.indexWhere((a) => a.callId == callId);
  if (index != -1) {
    agents[index] = agents[index].copyWith(
      ref: CollabAgentRef(
        threadId: newThreadId,
        agentNickname: nickname,
        agentRole: role,
      ),
      status: status,
      message: message,
    );
  } else {
    agents.add(
      CollabAgentEntry(
        callId: callId,
        ref: CollabAgentRef(
          threadId: newThreadId,
          agentNickname: nickname,
          agentRole: role,
        ),
        status: status,
        prompt: _asString(params['prompt']),
        message: message,
        senderThreadId: _asString(params['sender_thread_id']),
      ),
    );
  }

  return state.copyWith(collabAgents: agents);
}

SessionState _onCollabInteractionEnd(
  SessionState state,
  Map<String, dynamic> params,
) {
  final receiverThreadId = _asString(params['receiver_thread_id']) ?? '';
  if (receiverThreadId.isEmpty) return state;

  final status = parseAgentStatus(params['status']);
  final message = parseAgentStatusMessage(params['status']);
  final nickname = _asString(params['receiver_agent_nickname']);
  final role = _asString(params['receiver_agent_role']);

  return _updateCollabAgentByThreadId(
    state,
    threadId: receiverThreadId,
    status: status,
    message: message,
    nickname: nickname,
    role: role,
  );
}

SessionState _onCollabWaitingEnd(
  SessionState state,
  Map<String, dynamic> params,
) {
  final statusesMap = params['statuses'];
  if (statusesMap is! Map) return state;

  var next = state;
  for (final entry in statusesMap.entries) {
    final threadId = entry.key.toString();
    final status = parseAgentStatus(entry.value);
    final message = parseAgentStatusMessage(entry.value);
    next = _updateCollabAgentByThreadId(
      next,
      threadId: threadId,
      status: status,
      message: message,
    );
  }
  return next;
}

SessionState _onCollabCloseEnd(
  SessionState state,
  Map<String, dynamic> params,
) {
  final receiverThreadId = _asString(params['receiver_thread_id']) ?? '';
  if (receiverThreadId.isEmpty) return state;

  return _updateCollabAgentByThreadId(
    state,
    threadId: receiverThreadId,
    status: CollabAgentStatus.shutdown,
  );
}

SessionState _onCollabResumeEnd(
  SessionState state,
  Map<String, dynamic> params,
) {
  final receiverThreadId = _asString(params['receiver_thread_id']) ?? '';
  if (receiverThreadId.isEmpty) return state;

  final status = parseAgentStatus(params['status']);
  final message = parseAgentStatusMessage(params['status']);

  return _updateCollabAgentByThreadId(
    state,
    threadId: receiverThreadId,
    status: status,
    message: message,
  );
}

SessionState _updateCollabAgentByThreadId(
  SessionState state, {
  required String threadId,
  required CollabAgentStatus status,
  String? message,
  String? nickname,
  String? role,
}) {
  final agents = <CollabAgentEntry>[...state.collabAgents];
  final index = agents.indexWhere((a) => a.ref.threadId == threadId);
  if (index == -1) return state;

  var ref = agents[index].ref;
  if (nickname != null || role != null) {
    ref = CollabAgentRef(
      threadId: threadId,
      agentNickname: nickname ?? ref.agentNickname,
      agentRole: role ?? ref.agentRole,
    );
  }

  agents[index] = agents[index].copyWith(
    ref: ref,
    status: status,
    message: message,
  );

  return state.copyWith(collabAgents: agents);
}

SessionState _onStreamError(SessionState state, Map<String, dynamic> params) {
  final message =
      _asString(params['message']) ??
      _asString(asMap(params['error'])['message']) ??
      'stream error';
  return state.copyWith(
    statusHeader: 'Stream error: $message',
    pendingStatusRestore: false,
  );
}

SessionState _onBackgroundStatus(
  SessionState state,
  Map<String, dynamic> params,
) {
  final kind =
      (_asString(params['kind']) ??
              _asString(params['type']) ??
              _asString(params['event']) ??
              '')
          .toLowerCase();
  final message = (_asString(params['message']) ?? '').toLowerCase();

  final waiting =
      kind.contains('wait') ||
      message.contains('waiting for background terminal') ||
      (message.contains('background terminal') && message.contains('waiting'));
  if (waiting) {
    return state.copyWith(
      statusHeader: 'Waiting for background terminal',
      pendingStatusRestore: false,
    );
  }

  final finished =
      kind.contains('finished') ||
      kind.contains('completed') ||
      message.contains('background terminal finished');
  if (finished) {
    return state.copyWith(pendingStatusRestore: true);
  }

  final errored =
      kind.contains('error') ||
      message.contains('background terminal error') ||
      message.contains('failed');
  if (errored) {
    return state.copyWith(
      statusHeader: 'Background terminal error',
      pendingStatusRestore: false,
    );
  }

  return state;
}

SessionState _onToolDetailsChunk(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
  required String fallbackTitle,
  required String chunk,
  required bool append,
}) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      chunk.isEmpty) {
    return state;
  }

  final cells = <TimelineCell>[...state.timelineCells];
  var index = _buildCellIndex(cells);
  final phase = _startSecondaryPhase(
    cells,
    index: index,
    turnId: turnId,
    timestamp: timestamp,
    phaseClosedByItemId: itemId,
  );
  index = phase.index;

  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = cells.findIndexById(cellId);

  final isPlan = fallbackTitle == 'plan';
  final cellKind = isPlan ? TimelineCellKind.plan : TimelineCellKind.toolCall;
  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: cellKind,
        status: TimelineCellStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        isCollapsed: !isPlan,
        title: fallbackTitle,
        markdownText: isPlan ? chunk : null,
        detailsText: chunk,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    final currentDetails = existing.detailsText ?? '';
    final detailsText = append ? '$currentDetails$chunk' : chunk;
    final updatedMarkdown = isPlan
        ? (append ? '${existing.markdownText ?? ''}$chunk' : chunk)
        : existing.markdownText;
    final preservedKind = switch (existing.kind) {
      TimelineCellKind.reasoning => TimelineCellKind.reasoning,
      TimelineCellKind.plan => TimelineCellKind.plan,
      _ => TimelineCellKind.toolCall,
    };
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: preservedKind,
      status: TimelineCellStatus.inProgress,
      markdownText: updatedMarkdown,
      detailsText: detailsText,
      updatedAt: timestamp,
    );
  }

  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    statusHeader: 'Working',
    pendingStatusRestore: false,
    clearActiveStreamingAssistantCellId: phase.clearActiveStreamingAssistant,
  );
}

SessionState _onItemStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final item = asMap(params['item']);
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

  if (itemType == 'agentMessage') {
    final phase = _mergeAgentPhase(
      previousPhase: state.agentMessagePhaseByItemId[itemId],
      incomingPhase: _normalizeAgentPhase(_asString(item['phase'])),
    );
    final nextByItem = <String, String>{...state.agentMessagePhaseByItemId};
    nextByItem[itemId] = phase;

    final nextFinalByTurn = <String, String>{...state.finalAnswerItemIdByTurn};
    if (phase == 'final_answer') {
      nextFinalByTurn[turnId] = itemId;
    }

    var nextState = state.copyWith(
      agentMessagePhaseByItemId: nextByItem,
      finalAnswerItemIdByTurn: nextFinalByTurn,
    );
    if (phase == 'final_answer') {
      nextState = _reclassifyUnknownAssistantCellsForTurn(
        nextState,
        turnId: turnId,
        finalItemId: itemId,
        timestamp: timestamp,
      );
    }
    return nextState;
  }

  if (itemType == 'userMessage') {
    return state;
  }

  final isContextCompaction = itemType == 'contextCompaction';

  final cells = <TimelineCell>[...state.timelineCells];
  var index = _buildCellIndex(cells);
  final phase = _startSecondaryPhase(
    cells,
    index: index,
    turnId: turnId,
    timestamp: timestamp,
    phaseClosedByItemId: itemId,
  );
  index = phase.index;

  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = cells.findIndexById(cellId);
  final kind = _resolveCellKind(itemType);
  final existingMetadata = existingIndex == -1
      ? const <String, dynamic>{}
      : cells[existingIndex].metadata;
  final itemMetadata = _normalizeItemMetadata(
    itemType,
    item,
    previous: existingMetadata,
  );

  final title = _resolveItemTitle(kind, itemType, itemMetadata);
  final subtitle = _itemSubtitle(itemType, itemMetadata);
  final markdownText = kind == TimelineCellKind.reasoning
      ? (_reasoningSummary(itemMetadata).isEmpty
            ? null
            : _reasoningSummary(itemMetadata))
      : null;
  final detailsText =
      kind == TimelineCellKind.toolCall || kind == TimelineCellKind.subAgent
      ? _itemDetails(itemType, itemMetadata)
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
    isCollapsed: kind != TimelineCellKind.plan,
    title: title,
    subtitle: subtitle,
    markdownText: markdownText,
    detailsText: detailsText,
    metadata: itemMetadata,
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
      updatedAt: timestamp,
    );
  }

  final isPlan = itemType == 'plan';
  final isExecLike = kind == TimelineCellKind.toolCall && !isPlan;
  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    statusHeader: itemType == 'reasoning' ? 'Thinking' : 'Working',
    pendingStatusRestore: itemType == 'reasoning',
    activeExecCellId: isExecLike ? cellId : state.activeExecCellId,
    clearActiveExecCellId: !isExecLike && state.activeExecCellId == cellId,
    activePlanCellId: isPlan ? cellId : state.activePlanCellId,
    clearActivePlanCellId: !isPlan && state.activePlanCellId == cellId,
    clearActiveStreamingAssistantCellId: phase.clearActiveStreamingAssistant,
    contextUsage: isContextCompaction
        ? state.contextUsage.copyWith(isCompacting: true)
        : state.contextUsage,
  );
}

SessionState _onItemCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final item = asMap(params['item']);
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

  final isContextCompaction = itemType == 'contextCompaction';

  if (itemType == 'agentMessage') {
    final phase = _mergeAgentPhase(
      previousPhase: state.agentMessagePhaseByItemId[itemId],
      incomingPhase: _normalizeAgentPhase(_asString(item['phase'])),
    );
    var nextState = state;
    final nextByItem = <String, String>{...state.agentMessagePhaseByItemId};
    nextByItem[itemId] = phase;
    nextState = nextState.copyWith(agentMessagePhaseByItemId: nextByItem);
    if (phase == 'final_answer') {
      final nextFinalByTurn = <String, String>{
        ...state.finalAnswerItemIdByTurn,
      };
      nextFinalByTurn[turnId] = itemId;
      nextState = nextState.copyWith(finalAnswerItemIdByTurn: nextFinalByTurn);
      nextState = _reclassifyUnknownAssistantCellsForTurn(
        nextState,
        turnId: turnId,
        finalItemId: itemId,
        timestamp: timestamp,
      );
    }
    return _onAssistantItemCompleted(
      nextState,
      turnId: turnId,
      itemId: itemId,
      item: item,
      timestamp: timestamp,
    );
  }

  final cells = <TimelineCell>[...state.timelineCells];
  final index = _buildCellIndex(cells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = cells.findIndexById(cellId);
  final kind = _resolveCellKind(itemType);
  final existingMetadata = existingIndex == -1
      ? const <String, dynamic>{}
      : cells[existingIndex].metadata;
  final itemMetadata = _normalizeItemMetadata(
    itemType,
    item,
    previous: existingMetadata,
  );
  final status =
      _statusFromString(_asString(item['status'])) ??
      TimelineCellStatus.completed;

  final title = _resolveItemTitle(kind, itemType, itemMetadata);
  final subtitle = _itemSubtitle(itemType, itemMetadata);
  var reasoningText = _reasoningSummary(itemMetadata);
  if (kind == TimelineCellKind.reasoning &&
      reasoningText.isEmpty &&
      state.reasoningBufferByItemId.containsKey(itemId)) {
    reasoningText = state.reasoningBufferByItemId[itemId] ?? '';
  }
  final markdownText = kind == TimelineCellKind.reasoning
      ? (reasoningText.isEmpty ? null : reasoningText)
      : kind == TimelineCellKind.plan
      ? (existingIndex == -1 ? null : cells[existingIndex].markdownText)
      : null;
  final detailsText = _itemDetails(itemType, itemMetadata);

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
        isCollapsed: kind != TimelineCellKind.plan,
        title: title,
        subtitle: subtitle,
        markdownText: markdownText,
        detailsText: detailsText,
        metadata: itemMetadata,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    final mergedReasoning = kind == TimelineCellKind.reasoning
        ? _mergeFinalText(existing.markdownText ?? '', markdownText ?? '')
        : kind == TimelineCellKind.plan
        ? existing.markdownText
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
      metadata: itemMetadata,
      updatedAt: timestamp,
    );
  }

  final nextReasoningBuffer = <String, String>{
    ...state.reasoningBufferByItemId,
  };
  nextReasoningBuffer.remove(itemId);
  _upsertExitedReviewBodyCell(
    cells,
    turnId: turnId,
    itemId: itemId,
    itemType: itemType,
    itemMetadata: itemMetadata,
    timestamp: timestamp,
  );

  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    reasoningBufferByItemId: nextReasoningBuffer,
    statusHeader: itemType == 'reasoning' ? 'Working' : state.statusHeader,
    pendingStatusRestore: itemType == 'reasoning',
    clearActiveExecCellId: state.activeExecCellId == cellId,
    clearActivePlanCellId: state.activePlanCellId == cellId,
    contextUsage: isContextCompaction
        ? state.contextUsage.copyWith(isCompacting: false)
        : state.contextUsage,
  );
}

void _upsertExitedReviewBodyCell(
  List<TimelineCell> cells, {
  required String turnId,
  required String itemId,
  required String itemType,
  required Map<String, dynamic> itemMetadata,
  required DateTime timestamp,
}) {
  if (itemType != 'exitedReviewMode') {
    return;
  }

  final bodyCellId = 'review-exit-body-$itemId';
  final existingIndex = cells.findIndexById(bodyCellId);
  final reviewText = (_asString(itemMetadata['review']) ?? '').trim();

  if (reviewText.isEmpty) {
    if (existingIndex != -1) {
      cells.removeAt(existingIndex);
    }
    return;
  }

  final bodyCell = TimelineCell(
    id: bodyCellId,
    turnId: turnId,
    kind: TimelineCellKind.progressText,
    status: TimelineCellStatus.completed,
    createdAt: timestamp,
    updatedAt: timestamp,
    markdownText: reviewText,
    metadata: const <String, dynamic>{
      TimelineCellMetadata.uiPlacementKey: TimelineCellMetadata.outsideWorked,
      'reviewExitBody': true,
    },
  );

  if (existingIndex == -1) {
    cells.add(bodyCell);
    return;
  }

  cells[existingIndex] = cells[existingIndex].copyWith(
    turnId: turnId,
    status: TimelineCellStatus.completed,
    markdownText: reviewText,
    metadata: const <String, dynamic>{
      TimelineCellMetadata.uiPlacementKey: TimelineCellMetadata.outsideWorked,
      'reviewExitBody': true,
    },
    updatedAt: timestamp,
  );
}

SessionState _onAssistantItemCompleted(
  SessionState state, {
  required String turnId,
  required String itemId,
  required Map<String, dynamic> item,
  required DateTime timestamp,
}) {
  var nextState = state;
  if (nextState.activeAgentStreamItemId == itemId &&
      nextState.activeAgentStreamTurnId == turnId) {
    nextState = _flushActiveAgentStreamToQueue(nextState, timestamp);
    var guard = 0;
    while (nextState.streamQueue.isNotEmpty && guard < 200) {
      nextState = reduceCommitTick(
        nextState,
        scope: CommitTickScope.anyMode,
        now: timestamp,
      );
      guard += 1;
    }
  }

  final phase = _resolveAgentPhase(
    nextState,
    itemId: itemId,
    turnId: turnId,
    item: item,
  );
  final finalText = _assistantFinalText(item);
  final cells = <TimelineCell>[...nextState.timelineCells];
  final shouldClearActiveStream =
      nextState.activeAgentStreamItemId == itemId &&
      nextState.activeAgentStreamTurnId == turnId;
  final status =
      _statusFromString(_asString(item['status'])) ??
      TimelineCellStatus.completed;

  if (phase == 'commentary') {
    if (finalText.trim().isNotEmpty &&
        !_hasProgressTextForItem(
          cells,
          turnId: turnId,
          itemId: itemId,
        )) {
      cells.add(
        TimelineCell(
          id: 'commentary-$turnId-${timestamp.microsecondsSinceEpoch}',
          turnId: turnId,
          itemId: itemId,
          kind: TimelineCellKind.progressText,
          status: TimelineCellStatus.completed,
          createdAt: timestamp,
          updatedAt: timestamp,
          markdownText: finalText,
          metadata: <String, dynamic>{
            'isInterim': true,
            'streamPhase': 'commentary',
            'streamItemId': itemId,
            'streamCommitted': false,
            'source': 'item_completed',
          },
        ),
      );
    }
    return nextState.copyWith(
      timelineCells: cells,
      turnHadWorkActivity: true,
      clearActiveAgentStreamItemId: shouldClearActiveStream,
      clearActiveAgentStreamTurnId: shouldClearActiveStream,
      clearActiveAgentStreamPhase: shouldClearActiveStream,
      clearActiveAgentStreamLastDeltaAtMs: shouldClearActiveStream,
      clearActiveStreamingAssistantCellId:
          shouldClearActiveStream &&
          (nextState.activeStreamingAssistantCellId ?? '').isNotEmpty,
    );
  }

  final hasFinalAuthorityForTurn =
      nextState.finalAnswerItemIdByTurn[turnId] == itemId;
  final shouldTreatAsFinal =
      phase == 'final_answer' ||
      (phase == 'unknown' &&
          (hasFinalAuthorityForTurn || finalText.isNotEmpty));
  if (!shouldTreatAsFinal) {
    return nextState.copyWith(
      clearActiveAgentStreamItemId: shouldClearActiveStream,
      clearActiveAgentStreamTurnId: shouldClearActiveStream,
      clearActiveAgentStreamPhase: shouldClearActiveStream,
      clearActiveAgentStreamLastDeltaAtMs: shouldClearActiveStream,
    );
  }

  final index = _buildCellIndex(cells);
  final streamCommittedForItem = _hasCommittedAssistantStreamTextForItem(
    cells,
    turnId: turnId,
    itemId: itemId,
  );

  var assistantCellId = itemId;
  final indexedByItemId = index.cellIdByItemId[itemId];
  if (indexedByItemId != null) {
    final indexedAt = cells.findIndexById(indexedByItemId);
    if (indexedAt != -1 &&
        cells[indexedAt].kind == TimelineCellKind.assistantMessage) {
      assistantCellId = indexedByItemId;
    }
  }
  if (assistantCellId == itemId) {
    for (final cell in cells.reversed) {
      if (cell.turnId == turnId &&
          cell.kind == TimelineCellKind.assistantMessage &&
          cell.itemId == itemId) {
        assistantCellId = cell.id;
        break;
      }
    }
  }

  final assistantMetadata = <String, dynamic>{
    ...item,
    'streamPhase': 'final_answer',
    if (streamCommittedForItem) 'dedupeMode': 'stream_commit_same_item_id',
    if (streamCommittedForItem) 'streamItemId': itemId,
    if (streamCommittedForItem) 'streamCommitted': true,
  };

  final existingIndex = cells.findIndexById(assistantCellId);
  if (existingIndex == -1 ||
      cells[existingIndex].kind != TimelineCellKind.assistantMessage) {
    final baseText = streamCommittedForItem ? '' : finalText;
    cells.add(
      TimelineCell(
        id: assistantCellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.assistantMessage,
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
        isStreaming: false,
        markdownText: baseText.isEmpty ? null : baseText,
        metadata: assistantMetadata,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    final mergedText = streamCommittedForItem
        ? (existing.markdownText ?? '')
        : finalText.isEmpty
        ? (existing.markdownText ?? '')
        : _mergeFinalText(existing.markdownText ?? '', finalText);
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      status: status,
      isStreaming: false,
      markdownText: mergedText,
      metadata: assistantMetadata,
      updatedAt: timestamp,
    );
  }

  _trimTrailingOverlapWorkedVsFinal(cells, turnId: turnId);

  final shouldClearStreaming =
      nextState.activeStreamingAssistantCellId == assistantCellId;
  return nextState.copyWith(
    timelineCells: cells,
    clearActiveStreamingAssistantCellId: shouldClearStreaming,
    clearActiveAgentStreamItemId: shouldClearActiveStream,
    clearActiveAgentStreamTurnId: shouldClearActiveStream,
    clearActiveAgentStreamPhase: shouldClearActiveStream,
    clearActiveAgentStreamLastDeltaAtMs: shouldClearActiveStream,
  );
}

bool _hasCommittedAssistantStreamTextForItem(
  List<TimelineCell> cells, {
  required String turnId,
  required String itemId,
}) {
  for (final cell in cells) {
    if (cell.turnId != turnId ||
        cell.kind != TimelineCellKind.assistantMessage) {
      continue;
    }
    if ((cell.markdownText ?? '').trim().isEmpty) {
      continue;
    }
    final metadata = cell.metadata;
    final streamCommitted = metadata['streamCommitted'] == true;
    if (!streamCommitted) {
      continue;
    }
    final streamItemId =
        _asString(metadata['streamItemId']) ??
        _asString(metadata['stream_item_id']) ??
        cell.itemId;
    if (streamItemId == itemId) {
      return true;
    }
  }
  return false;
}

bool _hasProgressTextForItem(
  List<TimelineCell> cells, {
  required String turnId,
  required String itemId,
}) {
  for (final cell in cells) {
    if (cell.turnId != turnId || cell.kind != TimelineCellKind.progressText) {
      continue;
    }
    final text = (cell.markdownText ?? '').trim();
    if (text.isEmpty) {
      continue;
    }
    final metadata = cell.metadata;
    final streamItemId =
        _asString(metadata['streamItemId']) ??
        _asString(metadata['stream_item_id']) ??
        cell.itemId;
    if (streamItemId == itemId) {
      return true;
    }
  }
  return false;
}

class _CellIndex {
  const _CellIndex({
    required this.assistantCellIdByTurn,
    required this.cellIdByItemId,
    required this.pendingUserCellIdQueue,
    required this.hasSecondaryByTurn,
    required this.activeProgressTextCellIdByTurn,
    required this.maxProgressPhaseByTurn,
  });

  final Map<String, String> assistantCellIdByTurn;
  final Map<String, String> cellIdByItemId;
  final List<String> pendingUserCellIdQueue;
  final Map<String, bool> hasSecondaryByTurn;
  final Map<String, String> activeProgressTextCellIdByTurn;
  final Map<String, int> maxProgressPhaseByTurn;
}

_CellIndex _buildCellIndex(List<TimelineCell> cells) {
  final assistantCellIdByTurn = <String, String>{};
  final cellIdByItemId = <String, String>{};
  final pendingUserCellIdQueue = <String>[];
  final hasSecondaryByTurn = <String, bool>{};
  final activeProgressTextCellIdByTurn = <String, String>{};
  final maxProgressPhaseByTurn = <String, int>{};

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
    final turnId = cell.turnId;
    if (turnId != null && _isSecondaryKind(cell.kind)) {
      hasSecondaryByTurn[turnId] = true;
    }
    if (turnId != null && cell.kind == TimelineCellKind.progressText) {
      if (cell.status == TimelineCellStatus.inProgress) {
        activeProgressTextCellIdByTurn[turnId] = cell.id;
      }
      final phase =
          _asInt(cell.metadata['progressPhaseIndex']) ??
          _asInt(cell.metadata['progress_phase_index']) ??
          0;
      final current = maxProgressPhaseByTurn[turnId];
      if (current == null || phase > current) {
        maxProgressPhaseByTurn[turnId] = phase;
      }
    }
  }

  return _CellIndex(
    assistantCellIdByTurn: assistantCellIdByTurn,
    cellIdByItemId: cellIdByItemId,
    pendingUserCellIdQueue: pendingUserCellIdQueue,
    hasSecondaryByTurn: hasSecondaryByTurn,
    activeProgressTextCellIdByTurn: activeProgressTextCellIdByTurn,
    maxProgressPhaseByTurn: maxProgressPhaseByTurn,
  );
}

class _SecondaryPhaseResult {
  const _SecondaryPhaseResult({
    required this.index,
    required this.clearActiveStreamingAssistant,
  });

  final _CellIndex index;
  final bool clearActiveStreamingAssistant;
}

_SecondaryPhaseResult _startSecondaryPhase(
  List<TimelineCell> cells, {
  required _CellIndex index,
  required String turnId,
  required DateTime timestamp,
  String? phaseClosedByItemId,
}) {
  var clearedAssistantStreaming = false;
  final activeProgressId = index.activeProgressTextCellIdByTurn[turnId];
  if (activeProgressId != null) {
    final activeProgressIndex = cells.findIndexById(activeProgressId);
    if (activeProgressIndex != -1) {
      final activeProgress = cells[activeProgressIndex];
      if (activeProgress.status == TimelineCellStatus.inProgress) {
        final metadata = <String, dynamic>{...activeProgress.metadata};
        if (phaseClosedByItemId != null && phaseClosedByItemId.isNotEmpty) {
          metadata['phaseClosedAtTurnItemId'] = phaseClosedByItemId;
        }
        cells[activeProgressIndex] = activeProgress.copyWith(
          status: TimelineCellStatus.completed,
          metadata: metadata,
          updatedAt: timestamp,
        );
      }
    }
  }

  final assistantCellId = index.assistantCellIdByTurn[turnId];
  if (assistantCellId != null) {
    final assistantIndex = cells.findIndexById(assistantCellId);
    if (assistantIndex != -1) {
      final assistant = cells[assistantIndex];
      final assistantText = assistant.markdownText ?? '';
      if (assistant.isStreaming && assistantText.trim().isNotEmpty) {
        final phase = (index.maxProgressPhaseByTurn[turnId] ?? -1) + 1;
        final progressCellId =
            'progress-$turnId-${timestamp.microsecondsSinceEpoch}';
        cells.add(
          TimelineCell(
            id: progressCellId,
            turnId: turnId,
            kind: TimelineCellKind.progressText,
            status: TimelineCellStatus.completed,
            createdAt: timestamp,
            updatedAt: timestamp,
            markdownText: assistantText,
            metadata: <String, dynamic>{
              'progressPhaseIndex': phase,
              'isInterim': true,
              'source': 'assistant_delta',
            },
          ),
        );
        cells[assistantIndex] = assistant.copyWith(
          clearMarkdownText: true,
          updatedAt: timestamp,
        );
        clearedAssistantStreaming = true;
      }
    }
  }

  return _SecondaryPhaseResult(
    index: _buildCellIndex(cells),
    clearActiveStreamingAssistant: clearedAssistantStreaming,
  );
}

String? _sanitizeInterimDeltaForDisplay(String delta) {
  final normalized = delta.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final trimmed = normalized.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (!_isHumanFacingInterimLine(trimmed)) {
    return null;
  }
  return normalized;
}

bool _isHumanFacingInterimLine(String line) {
  final lower = line.toLowerCase();
  if (lower.contains('finalizing response')) {
    return false;
  }
  if (lower.contains('background terminal finished')) {
    return false;
  }
  if (lower.contains('terminal finished with')) {
    return false;
  }
  if (RegExp(r'^(thread|turn|item)[/:]').hasMatch(lower)) {
    return false;
  }
  if (line.startsWith('{') && line.contains('"method"')) {
    return false;
  }
  return true;
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

bool _isSecondaryKind(TimelineCellKind kind) {
  return kind == TimelineCellKind.progressText ||
      kind == TimelineCellKind.reasoning ||
      kind == TimelineCellKind.toolCall ||
      kind == TimelineCellKind.subAgent ||
      kind == TimelineCellKind.systemNotice ||
      kind == TimelineCellKind.questionAnswer;
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

TimelineCellKind _resolveCellKind(String itemType) {
  return itemType == 'reasoning'
      ? TimelineCellKind.reasoning
      : itemType == 'plan'
      ? TimelineCellKind.plan
      : itemType == 'subAgent' ||
            itemType == 'remoteAgent' ||
            itemType == 'collabAgentToolCall'
      ? TimelineCellKind.subAgent
      : TimelineCellKind.toolCall;
}

String _resolveItemTitle(
  TimelineCellKind kind,
  String itemType,
  Map<String, dynamic> itemMetadata,
) {
  if (kind == TimelineCellKind.subAgent) {
    final fallbackTask = _itemTitle(itemType, itemMetadata);
    final tool = _asString(itemMetadata['tool']);
    final arguments =
        (itemMetadata['arguments'] as Map<String, dynamic>?) ??
        (tool != null ? <String, dynamic>{'tool': tool} : null);
    return _subAgentTitle(arguments, fallbackTask);
  }
  return _itemTitle(itemType, itemMetadata);
}

String _itemTitle(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      final classification = _classifyCommandExecution(item);
      final command = _asString(item['command']);
      if (classification.isExploratory) {
        return classification.verbLabel;
      }
      return command == null || command.isEmpty
          ? 'Ran command'
          : 'Ran $command';
    case 'fileChange':
      final count = _changesCount(item['changes']);
      if (count == null || count <= 0) {
        return 'Edited files';
      }
      return 'Edited $count ${count == 1 ? 'file' : 'files'}';
    case 'mcpToolCall':
      final server = _asString(item['server']) ?? 'server';
      final tool = _asString(item['tool']) ?? 'tool';
      return 'MCP: $server/$tool';
    case 'webSearch':
      final action = _webSearchActionLabel(item['action']);
      return action == null ? 'Web search' : 'Web search: $action';
    case 'reasoning':
      return 'Thinking';
    case 'plan':
      return 'plan';
    case 'contextCompaction':
      return 'Compacting context';
    case 'enteredReviewMode':
      return 'Preparing review';
    case 'exitedReviewMode':
      return 'Review finished';
    case 'collabAgentToolCall':
      return 'Running sub-agent';
    case 'subAgent':
    case 'remoteAgent':
      return 'Sub-agent task';
    default:
      return itemType;
  }
}

String? _itemSubtitle(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      final classification = _classifyCommandExecution(item);
      if (classification.isExploratory) {
        return _asString(item['command']);
      }
      return _asString(item['cwd']);
    case 'fileChange':
      return _changesPathsSubtitle(item['changes']);
    case 'webSearch':
      return _asString(item['query']) ?? _asString(item['url']);
    case 'mcpToolCall':
      return _asString(item['status']);
    case 'collabAgentToolCall':
    case 'subAgent':
    case 'remoteAgent':
      return _asString(item['task']) ?? _asString(item['description']);
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
    case 'exitedReviewMode':
      return null;
    default:
      return _encode(item);
  }
}

Map<String, dynamic> _normalizeItemMetadata(
  String itemType,
  Map<String, dynamic> item, {
  Map<String, dynamic> previous = const <String, dynamic>{},
}) {
  final metadata = <String, dynamic>{...previous, ...item};
  if (itemType != 'commandExecution') {
    return metadata;
  }

  final classification = _classifyCommandExecution(metadata);
  metadata['commandActionsNormalized'] = classification.normalizedActions;
  metadata['isExploratory'] = classification.isExploratory;
  if (classification.exploreBucket == null) {
    metadata.remove('exploreBucket');
  } else {
    metadata['exploreBucket'] = classification.exploreBucket;
  }
  return metadata;
}

class _CommandClassification {
  const _CommandClassification({
    required this.verbLabel,
    required this.normalizedActions,
    required this.isExploratory,
    required this.exploreBucket,
  });

  final String verbLabel;
  final List<String> normalizedActions;
  final bool isExploratory;
  final String? exploreBucket;
}

_CommandClassification _classifyCommandExecution(Map<String, dynamic> item) {
  var normalizedActions = _extractCommandActionsNormalized(item);
  if (normalizedActions.isEmpty) {
    final heuristic = _classifyCommandByHeuristic(_asString(item['command']));
    normalizedActions = <String>[heuristic];
  }

  final hasSearch = normalizedActions.contains('search');
  final hasRead = normalizedActions.contains('read');
  final hasList = normalizedActions.contains('list');
  final verbLabel = hasSearch
      ? 'Search'
      : hasRead
      ? 'Read'
      : hasList
      ? 'List'
      : 'Ran';
  final isExploratory = hasSearch || hasRead || hasList;
  final exploreBucket = hasSearch
      ? 'search'
      : (hasRead || hasList ? 'file' : null);
  return _CommandClassification(
    verbLabel: verbLabel,
    normalizedActions: normalizedActions,
    isExploratory: isExploratory,
    exploreBucket: exploreBucket,
  );
}

List<String> _extractCommandActionsNormalized(Map<String, dynamic> item) {
  final normalizedFromMetadata = item['commandActionsNormalized'];
  if (normalizedFromMetadata is List) {
    final values = <String>[];
    for (final entry in normalizedFromMetadata) {
      final value = _normalizeCommandAction(entry);
      if (value != null && !values.contains(value)) {
        values.add(value);
      }
    }
    if (values.isNotEmpty) {
      return values;
    }
  }

  final rawActions = item['commandActions'];
  if (rawActions is List) {
    final values = <String>[];
    for (final raw in rawActions) {
      final value = _normalizeCommandAction(raw);
      if (value != null && !values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  return const <String>[];
}

String? _normalizeCommandAction(dynamic raw) {
  final token = switch (raw) {
    String value => value,
    Map map =>
      _asString(map['type']) ??
          _asString(map['action']) ??
          _asString(map['name']),
    _ => null,
  };
  if (token == null || token.isEmpty) {
    return null;
  }

  final value = token.toLowerCase();
  if (value == 'search') {
    return 'search';
  }
  if (value == 'read' || value == 'filesystemread') {
    return 'read';
  }
  if (value == 'listfiles' || value == 'list_files' || value == 'list') {
    return 'list';
  }
  if (value == 'unknown') {
    return 'ran';
  }
  return null;
}

String _classifyCommandByHeuristic(String? command) {
  final raw = (command ?? '').trim().toLowerCase();
  if (raw.isEmpty) {
    return 'ran';
  }

  if (raw.startsWith('rg --files') ||
      raw.startsWith('rga --files') ||
      raw.startsWith('git ls-files') ||
      RegExp(r'^(ls|tree|eza|exa|du|fd)\b').hasMatch(raw)) {
    return 'list';
  }

  if (RegExp(r'^(git grep)\b').hasMatch(raw) ||
      RegExp(r'^(rg|rga|grep|egrep|fgrep)\b').hasMatch(raw)) {
    return 'search';
  }

  if (RegExp(r'^(cat|bat|less|head|tail)\b').hasMatch(raw) ||
      raw.startsWith('sed -n')) {
    return 'read';
  }

  return 'ran';
}

String? _webSearchActionLabel(dynamic rawAction) {
  final action = _asString(rawAction)?.toLowerCase();
  return switch (action) {
    null => null,
    'search' => 'Search',
    'open_page' || 'openpage' || 'open' => 'Open page',
    'find_in_page' || 'findinpage' || 'find' => 'Find in page',
    _ => null,
  };
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
        final map = asMap(entry);
        if ((_asString(map['type']) ?? '').toLowerCase() == 'text') {
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

Map<String, dynamic> _normalizeLegacyAssistantCompletionItem(
  Map<String, dynamic> item, {
  required String phase,
}) {
  final contentText = _legacyAssistantContentText(item);
  final text = contentText.isNotEmpty
      ? contentText
      : _asString(item['text']) ?? _asString(item['message']) ?? '';
  return <String, dynamic>{
    ...item,
    'type': 'agentMessage',
    'phase': phase,
    'status': _asString(item['status']) ?? 'completed',
    'text': text,
  };
}

String _legacyAssistantContentText(Map<String, dynamic> item) {
  final content = item['content'];
  if (content is! List) {
    return '';
  }
  final buffer = StringBuffer();
  for (final entry in content) {
    if (entry is! Map) {
      continue;
    }
    final map = asMap(entry);
    if ((_asString(map['type']) ?? '').toLowerCase() != 'text') {
      continue;
    }
    final text = _asString(map['text']);
    if (text == null || text.isEmpty) {
      continue;
    }
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }
    buffer.write(text);
  }
  return buffer.toString();
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
  final usage = asMap(turn['usage']);
  final tokenUsage = asMap(turn['tokenUsage']);
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

int? _changesCount(dynamic rawChanges) {
  if (rawChanges is List) {
    return rawChanges.length;
  }
  return null;
}

String? _changesPathsSubtitle(dynamic rawChanges) {
  if (rawChanges is! List || rawChanges.isEmpty) {
    return null;
  }

  final paths = <String>[];
  for (final entry in rawChanges) {
    final map = asMap(entry);
    final path =
        _asString(map['path']) ??
        _asString(map['newPath']) ??
        _asString(map['new_path']) ??
        _asString(map['oldPath']) ??
        _asString(map['old_path']);
    if (path != null && path.isNotEmpty) {
      paths.add(path);
    }
  }

  if (paths.isEmpty) {
    final count = rawChanges.length;
    return '$count ${count == 1 ? 'change' : 'changes'}';
  }

  const maxVisible = 2;
  if (paths.length <= maxVisible) {
    return paths.join(', ');
  }

  final hidden = paths.length - maxVisible;
  final preview = paths.take(maxVisible).join(', ');
  return '$preview +$hidden more';
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

String _subAgentTitle(Map<String, dynamic>? arguments, String? fallbackTask) {
  final tool = _asString(arguments?['tool']);
  switch (tool) {
    case toolNameSpawnAgent:
      return 'Spawning sub-agent';
    case toolNameWait:
      return 'Waiting for sub-agent';
    case null:
    case '':
      return fallbackTask ?? 'Sub-agent task';
    default:
      // For any other tool, format it nicely
      return 'Running ${tool.replaceAll('_', ' ')}';
  }
}

SessionState _onSubAgentStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  if (turnId == null || turnId.isEmpty || itemId == null || itemId.isEmpty) {
    return state;
  }
  final cells = <TimelineCell>[...state.timelineCells];
  var index = _buildCellIndex(cells);
  final phase = _startSecondaryPhase(
    cells,
    index: index,
    turnId: turnId,
    timestamp: timestamp,
    phaseClosedByItemId: itemId,
  );
  index = phase.index;
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = cells.findIndexById(cellId);
  final fallbackTask = _asString(params['task']) ?? 'Sub-agent task';
  final arguments = params['arguments'] as Map<String, dynamic>?;
  final title = _subAgentTitle(arguments, fallbackTask);
  final metadata = <String, dynamic>{
    'isSubAgent': true,
    if (arguments != null) 'arguments': arguments,
  };
  if (existingIndex == -1) {
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.subAgent,
        status: TimelineCellStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        isCollapsed: true,
        title: title,
        detailsText: arguments != null ? _encode(arguments) : null,
        metadata: metadata,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    cells[existingIndex] = existing.copyWith(
      turnId: turnId,
      itemId: itemId,
      kind: TimelineCellKind.subAgent,
      status: TimelineCellStatus.inProgress,
      title: title,
      updatedAt: timestamp,
      metadata: <String, dynamic>{...existing.metadata, ...metadata},
    );
  }
  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    statusHeader: title,
    pendingStatusRestore: false,
    clearActiveStreamingAssistantCellId: phase.clearActiveStreamingAssistant,
  );
}

SessionState _onSubAgentDelta(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  final delta = _asString(params['delta']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      delta == null ||
      delta.isEmpty) {
    return state;
  }
  final index = _buildCellIndex(state.timelineCells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = state.timelineCells.findIndexById(cellId);
  if (existingIndex == -1) {
    return state;
  }
  final cells = <TimelineCell>[...state.timelineCells];
  final existing = cells[existingIndex];
  final currentOutput = existing.metadata['output'] as String? ?? '';
  // Limit output growth to prevent unbounded memory usage (max ~50KB)
  const maxOutputLength = 50000;
  String newOutput;
  if (currentOutput.length >= maxOutputLength) {
    newOutput = currentOutput;
  } else if (currentOutput.isEmpty) {
    newOutput = delta.length > maxOutputLength
        ? delta.substring(0, maxOutputLength)
        : delta;
  } else {
    newOutput = '$currentOutput\n$delta';
    if (newOutput.length > maxOutputLength) {
      newOutput = newOutput.substring(0, maxOutputLength);
    }
  }
  cells[existingIndex] = existing.copyWith(
    updatedAt: timestamp,
    metadata: <String, dynamic>{...existing.metadata, 'output': newOutput},
  );
  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    statusHeader: existing.title,
    pendingStatusRestore: false,
  );
}

SessionState _onSubAgentCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime timestamp,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  if (turnId == null || turnId.isEmpty || itemId == null || itemId.isEmpty) {
    return state;
  }
  final index = _buildCellIndex(state.timelineCells);
  final cellId = index.cellIdByItemId[itemId] ?? itemId;
  final existingIndex = state.timelineCells.findIndexById(cellId);
  final result = params['result'] as Map<String, dynamic>?;
  final success = result?['success'] as bool? ?? true;
  final status = success
      ? TimelineCellStatus.completed
      : TimelineCellStatus.failed;
  final cells = <TimelineCell>[...state.timelineCells];
  if (existingIndex == -1) {
    final fallbackTask = _asString(params['task']) ?? 'Sub-agent task';
    final arguments = params['arguments'] as Map<String, dynamic>?;
    final title = _subAgentTitle(arguments, fallbackTask);
    final metadata = <String, dynamic>{
      'isSubAgent': true,
      if (arguments != null) 'arguments': arguments,
      if (result != null) 'result': result,
    };
    cells.add(
      TimelineCell(
        id: cellId,
        turnId: turnId,
        itemId: itemId,
        kind: TimelineCellKind.subAgent,
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
        isCollapsed: true,
        title: title,
        metadata: metadata,
      ),
    );
  } else {
    final existing = cells[existingIndex];
    final metadata = <String, dynamic>{
      ...existing.metadata,
      if (result != null) 'result': result,
    };
    cells[existingIndex] = existing.copyWith(
      status: status,
      updatedAt: timestamp,
      metadata: metadata,
    );
  }
  return state.copyWith(
    timelineCells: cells,
    activeTurnId: turnId,
    turnHadWorkActivity: true,
    statusHeader: 'Working',
    pendingStatusRestore: false,
  );
}

import 'dart:convert';

import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';

SessionState appendOptimisticUserMessage(
  SessionState state, {
  required String text,
  DateTime? now,
}) {
  final createdAt = now ?? DateTime.now().toUtc();
  final message = TimelineMessage(
    id: 'user-${createdAt.microsecondsSinceEpoch}',
    turnId: null,
    role: TimelineRole.user,
    markdownText: text,
    isStreaming: false,
    createdAt: createdAt,
  );
  return state.copyWith(
    timelineMessages: <TimelineMessage>[...state.timelineMessages, message],
  );
}

SessionState reduceNotification(
  SessionState state,
  SessionNotificationEvent event, {
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now().toUtc();
  var next = _appendRawLog(state, event);
  final params = _asMap(event.payload['params']);

  switch (event.method) {
    case 'turn/started':
      return _onTurnStarted(next, params);
    case 'turn/completed':
      return _onTurnCompleted(next, params);
    case 'item/started':
      return _onItemStarted(next, params, timestamp);
    case 'item/completed':
      return _onItemCompleted(next, params, timestamp);
    case 'item/agentMessage/delta':
      return _onAgentMessageDelta(next, params, timestamp);
    case 'item/commandExecution/outputDelta':
      return _onActivityDelta(
        next,
        params,
        timestamp: timestamp,
        expectedKind: ActivityKind.commandExecution,
        defaultTitle: 'command execution',
      );
    case 'item/fileChange/outputDelta':
      return _onActivityDelta(
        next,
        params,
        timestamp: timestamp,
        expectedKind: ActivityKind.fileChange,
        defaultTitle: 'file change',
      );
    case 'item/reasoning/summaryTextDelta':
      return _onActivityDelta(
        next,
        params,
        timestamp: timestamp,
        expectedKind: ActivityKind.reasoning,
        defaultTitle: 'reasoning',
      );
    case 'item/plan/delta':
      return _onActivityDelta(
        next,
        params,
        timestamp: timestamp,
        expectedKind: ActivityKind.plan,
        defaultTitle: 'plan',
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

SessionState _onTurnStarted(SessionState state, Map<String, dynamic> params) {
  final turn = _asMap(params['turn']);
  final turnId = _asString(turn['id']);
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  var messages = state.timelineMessages;
  var userMessageId = _findLatestPendingUserMessageId(messages);
  if (userMessageId != null) {
    messages = messages
        .map((message) {
          if (message.id != userMessageId) {
            return message;
          }
          return message.copyWith(turnId: turnId);
        })
        .toList(growable: false);
  }

  final groups = _upsertTurnGroup(
    state.turnGroups,
    turnId: turnId,
    userMessageId: userMessageId,
  );

  return state.copyWith(
    timelineMessages: messages,
    turnGroups: groups,
    activeTurnId: turnId,
  );
}

SessionState _onTurnCompleted(SessionState state, Map<String, dynamic> params) {
  final turn = _asMap(params['turn']);
  final turnId = _asString(turn['id']);
  if (turnId == null || turnId.isEmpty) {
    return state;
  }

  final messages = state.timelineMessages
      .map((message) {
        if (message.turnId == turnId &&
            message.role == TimelineRole.assistant) {
          return message.copyWith(isStreaming: false);
        }
        return message;
      })
      .toList(growable: false);

  var clearStreaming = false;
  if (state.activeStreamingAssistantMessageId != null) {
    for (final message in messages) {
      if (message.id == state.activeStreamingAssistantMessageId &&
          message.turnId == turnId) {
        clearStreaming = true;
        break;
      }
    }
  }

  return state.copyWith(
    timelineMessages: messages,
    clearActiveStreamingAssistantMessageId: clearStreaming,
    clearActiveTurnId: state.activeTurnId == turnId,
  );
}

SessionState _onAgentMessageDelta(
  SessionState state,
  Map<String, dynamic> params,
  DateTime now,
) {
  final turnId = _asString(params['turnId']) ?? state.activeTurnId;
  final itemId = _asString(params['itemId']);
  final delta = _asString(params['delta']) ?? '';
  if (turnId == null || turnId.isEmpty || delta.isEmpty) {
    return state;
  }

  final group = _findTurnGroup(state.turnGroups, turnId);
  var assistantMessageId = group?.assistantMessageId;
  assistantMessageId ??= _findAssistantMessageIdByTurn(
    state.timelineMessages,
    turnId,
  );
  assistantMessageId ??= itemId ?? 'assistant-$turnId';

  var messageFound = false;
  final messages = state.timelineMessages
      .map((message) {
        if (message.id != assistantMessageId) {
          return message;
        }
        messageFound = true;
        return message.copyWith(
          turnId: turnId,
          markdownText: '${message.markdownText}$delta',
          isStreaming: true,
        );
      })
      .toList(growable: false);

  final nextMessages = messageFound
      ? messages
      : <TimelineMessage>[
          ...messages,
          TimelineMessage(
            id: assistantMessageId,
            turnId: turnId,
            role: TimelineRole.assistant,
            markdownText: delta,
            isStreaming: true,
            createdAt: now,
          ),
        ];

  final groups = _upsertTurnGroup(
    state.turnGroups,
    turnId: turnId,
    assistantMessageId: assistantMessageId,
  );

  return state.copyWith(
    timelineMessages: nextMessages,
    turnGroups: groups,
    activeStreamingAssistantMessageId: assistantMessageId,
    activeTurnId: turnId,
  );
}

SessionState _onItemStarted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime now,
) {
  final item = _asMap(params['item']);
  final turnId = _asString(params['turnId']) ?? _asString(item['turnId']);
  final itemId = _asString(item['id']);
  final itemType = _asString(item['type']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      itemType == null) {
    return state;
  }
  if (itemType == 'agentMessage' || itemType == 'userMessage') {
    return state;
  }

  final kind = _activityKindFromItemType(itemType);
  final started = TimelineActivityItem(
    id: itemId,
    turnId: turnId,
    kind: kind,
    title: _activityTitle(kind, item),
    subtitle: _activitySubtitle(kind, item),
    status: _activityStatusFromString(_asString(item['status'])),
    summary: _activitySummary(kind, item),
    details: _activityDetails(kind, item),
    startedAt: now,
  );

  return _upsertActivity(state, started, addToTurnGroup: true);
}

SessionState _onItemCompleted(
  SessionState state,
  Map<String, dynamic> params,
  DateTime now,
) {
  final item = _asMap(params['item']);
  final turnId = _asString(params['turnId']) ?? _asString(item['turnId']);
  final itemId = _asString(item['id']);
  final itemType = _asString(item['type']);
  if (turnId == null ||
      turnId.isEmpty ||
      itemId == null ||
      itemId.isEmpty ||
      itemType == null) {
    return state;
  }

  if (itemType == 'agentMessage') {
    return _onAssistantItemCompleted(
      state,
      turnId: turnId,
      itemId: itemId,
      item: item,
      now: now,
    );
  }

  if (itemType == 'userMessage') {
    return state;
  }

  final kind = _activityKindFromItemType(itemType);
  final existing = _findActivity(state.timelineActivities, itemId);
  final base =
      existing ??
      TimelineActivityItem(
        id: itemId,
        turnId: turnId,
        kind: kind,
        title: _activityTitle(kind, item),
        subtitle: _activitySubtitle(kind, item),
        status: TimelineActivityStatus.inProgress,
        summary: _activitySummary(kind, item),
        details: _activityDetails(kind, item),
        startedAt: now,
      );

  final completed = base.copyWith(
    kind: kind,
    title: _activityTitle(kind, item),
    subtitle: _activitySubtitle(kind, item),
    status: _activityStatusFromString(_asString(item['status'])),
    summary: _activitySummary(kind, item),
    details: _activityDetails(kind, item) ?? base.details,
    endedAt: now,
  );
  return _upsertActivity(state, completed, addToTurnGroup: true);
}

SessionState _onAssistantItemCompleted(
  SessionState state, {
  required String turnId,
  required String itemId,
  required Map<String, dynamic> item,
  required DateTime now,
}) {
  final finalText = _asString(item['text']) ?? '';
  final group = _findTurnGroup(state.turnGroups, turnId);
  var assistantMessageId = group?.assistantMessageId;
  assistantMessageId ??= _findAssistantMessageIdByTurn(
    state.timelineMessages,
    turnId,
  );
  assistantMessageId ??= itemId;

  var messageFound = false;
  final messages = state.timelineMessages
      .map((message) {
        if (message.id != assistantMessageId) {
          return message;
        }
        messageFound = true;
        final mergedText = _mergeAssistantText(message.markdownText, finalText);
        return message.copyWith(
          turnId: turnId,
          markdownText: mergedText,
          isStreaming: false,
        );
      })
      .toList(growable: false);

  final nextMessages = messageFound
      ? messages
      : <TimelineMessage>[
          ...messages,
          TimelineMessage(
            id: assistantMessageId,
            turnId: turnId,
            role: TimelineRole.assistant,
            markdownText: finalText,
            isStreaming: false,
            createdAt: now,
          ),
        ];

  final groups = _upsertTurnGroup(
    state.turnGroups,
    turnId: turnId,
    assistantMessageId: assistantMessageId,
  );

  final shouldClearStreaming =
      state.activeStreamingAssistantMessageId == assistantMessageId;
  return state.copyWith(
    timelineMessages: nextMessages,
    turnGroups: groups,
    clearActiveStreamingAssistantMessageId: shouldClearStreaming,
  );
}

SessionState _onActivityDelta(
  SessionState state,
  Map<String, dynamic> params, {
  required DateTime timestamp,
  required ActivityKind expectedKind,
  required String defaultTitle,
}) {
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

  final existing = _findActivity(state.timelineActivities, itemId);
  final base =
      existing ??
      TimelineActivityItem(
        id: itemId,
        turnId: turnId,
        kind: expectedKind,
        title: defaultTitle,
        status: TimelineActivityStatus.inProgress,
        summary: delta,
        details: '',
        startedAt: timestamp,
      );
  final mergedDetails = '${base.details ?? ''}$delta';
  final updated = base.copyWith(
    turnId: turnId,
    kind: expectedKind,
    status: TimelineActivityStatus.inProgress,
    summary: (base.summary?.isNotEmpty ?? false) ? base.summary : delta,
    details: mergedDetails,
  );
  return _upsertActivity(state, updated, addToTurnGroup: true);
}

SessionState _upsertActivity(
  SessionState state,
  TimelineActivityItem item, {
  required bool addToTurnGroup,
}) {
  var found = false;
  final activities = state.timelineActivities
      .map((candidate) {
        if (candidate.id != item.id) {
          return candidate;
        }
        found = true;
        return item;
      })
      .toList(growable: false);

  final nextActivities = found
      ? activities
      : <TimelineActivityItem>[...activities, item];
  final nextGroups = addToTurnGroup
      ? _upsertTurnGroup(
          state.turnGroups,
          turnId: item.turnId,
          addActivityItemId: item.id,
        )
      : state.turnGroups;

  return state.copyWith(
    timelineActivities: nextActivities,
    turnGroups: nextGroups,
  );
}

List<TimelineTurnGroup> _upsertTurnGroup(
  List<TimelineTurnGroup> groups, {
  required String turnId,
  String? userMessageId,
  String? assistantMessageId,
  String? addActivityItemId,
}) {
  var found = false;
  final updated = groups
      .map((group) {
        if (group.turnId != turnId) {
          return group;
        }
        found = true;

        var next = group;
        if (userMessageId != null) {
          next = next.copyWith(userMessageId: userMessageId);
        }
        if (assistantMessageId != null) {
          next = next.copyWith(assistantMessageId: assistantMessageId);
        }
        if (addActivityItemId != null &&
            !next.activityItemIds.contains(addActivityItemId)) {
          next = next.copyWith(
            activityItemIds: <String>[
              ...next.activityItemIds,
              addActivityItemId,
            ],
          );
        }
        return next;
      })
      .toList(growable: false);

  if (found) {
    return updated;
  }

  return <TimelineTurnGroup>[
    ...updated,
    TimelineTurnGroup(
      turnId: turnId,
      userMessageId: userMessageId,
      assistantMessageId: assistantMessageId,
      activityItemIds: addActivityItemId == null
          ? const <String>[]
          : <String>[addActivityItemId],
    ),
  ];
}

TimelineTurnGroup? _findTurnGroup(
  List<TimelineTurnGroup> groups,
  String turnId,
) {
  for (final group in groups) {
    if (group.turnId == turnId) {
      return group;
    }
  }
  return null;
}

TimelineActivityItem? _findActivity(
  List<TimelineActivityItem> activities,
  String itemId,
) {
  for (final activity in activities) {
    if (activity.id == itemId) {
      return activity;
    }
  }
  return null;
}

String? _findLatestPendingUserMessageId(List<TimelineMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.role == TimelineRole.user && message.turnId == null) {
      return message.id;
    }
  }
  return null;
}

String? _findAssistantMessageIdByTurn(
  List<TimelineMessage> messages,
  String turnId,
) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.role == TimelineRole.assistant && message.turnId == turnId) {
      return message.id;
    }
  }
  return null;
}

TimelineActivityStatus _activityStatusFromString(String? status) {
  return switch (status) {
    'completed' => TimelineActivityStatus.completed,
    'failed' => TimelineActivityStatus.failed,
    'declined' => TimelineActivityStatus.declined,
    _ => TimelineActivityStatus.inProgress,
  };
}

ActivityKind _activityKindFromItemType(String itemType) {
  return switch (itemType) {
    'commandExecution' => ActivityKind.commandExecution,
    'fileChange' => ActivityKind.fileChange,
    'mcpToolCall' => ActivityKind.mcpToolCall,
    'webSearch' => ActivityKind.webSearch,
    'reasoning' => ActivityKind.reasoning,
    'plan' => ActivityKind.plan,
    _ => ActivityKind.other,
  };
}

String _activityTitle(ActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    ActivityKind.commandExecution => _asString(item['command']) ?? 'command',
    ActivityKind.fileChange => 'file changes',
    ActivityKind.mcpToolCall =>
      '${_asString(item['server']) ?? 'mcp'}:${_asString(item['tool']) ?? 'tool'}',
    ActivityKind.webSearch => _asString(item['query']) ?? 'web search',
    ActivityKind.reasoning => 'reasoning',
    ActivityKind.plan => 'plan',
    ActivityKind.other => _asString(item['type']) ?? 'activity',
  };
}

String? _activitySubtitle(ActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    ActivityKind.commandExecution => _asString(item['cwd']),
    ActivityKind.fileChange => _changesSubtitle(item['changes']),
    ActivityKind.webSearch => _asString(item['action']),
    _ => null,
  };
}

String? _activitySummary(ActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    ActivityKind.commandExecution =>
      _asString(item['status']) == null ? null : 'status: ${item['status']}',
    ActivityKind.fileChange => _changesSubtitle(item['changes']),
    ActivityKind.mcpToolCall => _asString(item['status']),
    ActivityKind.webSearch => _asString(item['query']),
    ActivityKind.reasoning => _truncate(_reasoningSummary(item), 140),
    ActivityKind.plan => _truncate(_asString(item['text']) ?? '', 140),
    ActivityKind.other => _truncate(jsonEncode(item), 140),
  };
}

String? _activityDetails(ActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    ActivityKind.commandExecution =>
      _asString(item['aggregatedOutput']) ?? _asString(item['output']),
    ActivityKind.fileChange => _encodeIfNotEmpty(item['changes']),
    ActivityKind.mcpToolCall =>
      _asString(item['result']) ?? _encode(item['result']),
    ActivityKind.webSearch => _encode(item),
    ActivityKind.reasoning => _reasoningSummary(item),
    ActivityKind.plan => _asString(item['text']),
    ActivityKind.other => _encode(item),
  };
}

String _mergeAssistantText(String currentText, String finalText) {
  if (finalText.isEmpty) {
    return currentText;
  }
  if (currentText.isEmpty) {
    return finalText;
  }
  if (currentText == finalText) {
    return currentText;
  }
  if (finalText.startsWith(currentText)) {
    return finalText;
  }
  return finalText;
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
  return _asString(summary) ?? '';
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) {
    return value;
  }
  return '${value.substring(0, maxChars - 3)}...';
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

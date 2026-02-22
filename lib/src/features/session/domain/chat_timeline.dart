enum TimelineRole { user, assistant, system }

enum ActivityKind {
  commandExecution,
  fileChange,
  mcpToolCall,
  webSearch,
  reasoning,
  plan,
  other,
}

enum TimelineActivityStatus { inProgress, completed, failed, declined }

class TimelineMessage {
  const TimelineMessage({
    required this.id,
    required this.turnId,
    required this.role,
    required this.markdownText,
    required this.isStreaming,
    required this.createdAt,
  });

  final String id;
  final String? turnId;
  final TimelineRole role;
  final String markdownText;
  final bool isStreaming;
  final DateTime createdAt;

  TimelineMessage copyWith({
    String? id,
    String? turnId,
    bool clearTurnId = false,
    TimelineRole? role,
    String? markdownText,
    bool? isStreaming,
    DateTime? createdAt,
  }) {
    return TimelineMessage(
      id: id ?? this.id,
      turnId: clearTurnId ? null : (turnId ?? this.turnId),
      role: role ?? this.role,
      markdownText: markdownText ?? this.markdownText,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class TimelineActivityItem {
  const TimelineActivityItem({
    required this.id,
    required this.turnId,
    required this.kind,
    required this.title,
    this.subtitle,
    required this.status,
    this.summary,
    this.details,
    required this.startedAt,
    this.endedAt,
  });

  final String id;
  final String turnId;
  final ActivityKind kind;
  final String title;
  final String? subtitle;
  final TimelineActivityStatus status;
  final String? summary;
  final String? details;
  final DateTime startedAt;
  final DateTime? endedAt;

  TimelineActivityItem copyWith({
    String? id,
    String? turnId,
    ActivityKind? kind,
    String? title,
    String? subtitle,
    bool clearSubtitle = false,
    TimelineActivityStatus? status,
    String? summary,
    bool clearSummary = false,
    String? details,
    bool clearDetails = false,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return TimelineActivityItem(
      id: id ?? this.id,
      turnId: turnId ?? this.turnId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      status: status ?? this.status,
      summary: clearSummary ? null : (summary ?? this.summary),
      details: clearDetails ? null : (details ?? this.details),
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}

class TimelineTurnGroup {
  const TimelineTurnGroup({
    required this.turnId,
    this.userMessageId,
    this.assistantMessageId,
    this.activityItemIds = const <String>[],
  });

  final String turnId;
  final String? userMessageId;
  final String? assistantMessageId;
  final List<String> activityItemIds;

  TimelineTurnGroup copyWith({
    String? turnId,
    String? userMessageId,
    bool clearUserMessageId = false,
    String? assistantMessageId,
    bool clearAssistantMessageId = false,
    List<String>? activityItemIds,
  }) {
    return TimelineTurnGroup(
      turnId: turnId ?? this.turnId,
      userMessageId: clearUserMessageId
          ? null
          : (userMessageId ?? this.userMessageId),
      assistantMessageId: clearAssistantMessageId
          ? null
          : (assistantMessageId ?? this.assistantMessageId),
      activityItemIds: activityItemIds ?? this.activityItemIds,
    );
  }
}

enum TimelineCellKind {
  userMessage,
  assistantMessage,
  progressText,
  reasoning,
  toolCall,
  subAgent,
  plan,
  turnSeparator,
  systemNotice,
}

enum TimelineCellStatus { inProgress, completed, failed, declined, info }

class TimelineCell {
  const TimelineCell({
    required this.id,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.turnId,
    this.isStreaming = false,
    this.isCollapsed = false,
    this.title,
    this.subtitle,
    this.markdownText,
    this.detailsText,
    this.itemId,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String? turnId;
  final TimelineCellKind kind;
  final TimelineCellStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isStreaming;
  final bool isCollapsed;
  final String? title;
  final String? subtitle;
  final String? markdownText;
  final String? detailsText;
  final String? itemId;
  final Map<String, dynamic> metadata;

  TimelineCell copyWith({
    String? id,
    String? turnId,
    bool clearTurnId = false,
    TimelineCellKind? kind,
    TimelineCellStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isStreaming,
    bool? isCollapsed,
    String? title,
    bool clearTitle = false,
    String? subtitle,
    bool clearSubtitle = false,
    String? markdownText,
    bool clearMarkdownText = false,
    String? detailsText,
    bool clearDetailsText = false,
    String? itemId,
    bool clearItemId = false,
    Map<String, dynamic>? metadata,
  }) {
    return TimelineCell(
      id: id ?? this.id,
      turnId: clearTurnId ? null : (turnId ?? this.turnId),
      kind: kind ?? this.kind,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isStreaming: isStreaming ?? this.isStreaming,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      title: clearTitle ? null : (title ?? this.title),
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      markdownText: clearMarkdownText
          ? null
          : (markdownText ?? this.markdownText),
      detailsText: clearDetailsText ? null : (detailsText ?? this.detailsText),
      itemId: clearItemId ? null : (itemId ?? this.itemId),
      metadata: metadata ?? this.metadata,
    );
  }
}

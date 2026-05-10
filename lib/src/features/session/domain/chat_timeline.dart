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
  questionAnswer,
}

enum TimelineCellStatus { inProgress, completed, failed, declined, info }

/// Constants for TimelineCell metadata keys and values.
abstract class TimelineCellMetadata {
  /// Key for UI placement of timeline rows.
  static const String uiPlacementKey = 'uiPlacement';

  /// Value for placing a row outside the "Worked..." section.
  static const String outsideWorked = 'outside_worked';

  /// Key indicating a user message is a steering injection.
  static const String isSteeringKey = 'isSteering';
}

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

extension TimelineCellListExtension on List<TimelineCell> {
  int findIndexById(String id) {
    for (var i = 0; i < length; i++) {
      if (this[i].id == id) return i;
    }
    return -1;
  }
}

extension TimelineCellSerialization on TimelineCell {
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'turnId': turnId,
      'kind': kind.name,
      'status': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'isStreaming': isStreaming,
      'isCollapsed': isCollapsed,
      'title': title,
      'subtitle': subtitle,
      'markdownText': markdownText,
      'detailsText': detailsText,
      'itemId': itemId,
      'metadata': metadata,
    };
  }
}

TimelineCell timelineCellFromJson(Map<String, Object?> json) {
  final id = json['id'];
  final kindRaw = json['kind'];
  final statusRaw = json['status'];
  final createdAtRaw = json['createdAt'];
  final updatedAtRaw = json['updatedAt'];
  if (id is! String || id.isEmpty) {
    throw StateError('TimelineCell record missing id');
  }
  if (kindRaw is! String) {
    throw StateError('TimelineCell record missing kind');
  }
  if (statusRaw is! String) {
    throw StateError('TimelineCell record missing status');
  }
  if (createdAtRaw is! String) {
    throw StateError('TimelineCell record missing createdAt');
  }
  if (updatedAtRaw is! String) {
    throw StateError('TimelineCell record missing updatedAt');
  }
  final kind = _timelineCellKindFromName(kindRaw);
  final status = _timelineCellStatusFromName(statusRaw);
  final metadataRaw = json['metadata'];
  final metadata = metadataRaw is Map
      ? metadataRaw
            .map((key, value) => MapEntry(key.toString(), value))
            .cast<String, dynamic>()
      : const <String, dynamic>{};
  return TimelineCell(
    id: id,
    turnId: json['turnId'] as String?,
    kind: kind,
    status: status,
    createdAt: DateTime.parse(createdAtRaw).toUtc(),
    updatedAt: DateTime.parse(updatedAtRaw).toUtc(),
    isStreaming: false,
    isCollapsed: json['isCollapsed'] == true,
    title: json['title'] as String?,
    subtitle: json['subtitle'] as String?,
    markdownText: json['markdownText'] as String?,
    detailsText: json['detailsText'] as String?,
    itemId: json['itemId'] as String?,
    metadata: metadata,
  );
}

TimelineCellKind _timelineCellKindFromName(String name) {
  for (final kind in TimelineCellKind.values) {
    if (kind.name == name) return kind;
  }
  throw StateError('Unknown TimelineCellKind: $name');
}

TimelineCellStatus _timelineCellStatusFromName(String name) {
  for (final status in TimelineCellStatus.values) {
    if (status.name == name) return status;
  }
  throw StateError('Unknown TimelineCellStatus: $name');
}

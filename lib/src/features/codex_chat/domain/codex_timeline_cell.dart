import 'package:flutter/foundation.dart';

enum CodexTimelineKind {
  userMessage,
  assistantMessage,
  progressText,
  reasoning,
  toolCall,
  command,
  diff,
  subAgent,
  plan,
  turnSeparator,
  systemNotice,
  questionAnswer,
}

enum CodexTimelineStatus { inProgress, completed, failed, declined, info }

abstract final class CodexTimelineMetadata {
  static const uiPlacement = 'uiPlacement';
  static const outsideWorked = 'outside_worked';
  static const isSteering = 'isSteering';
}

@immutable
class CodexTimelineCell {
  const CodexTimelineCell({
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
    this.renderedMarkdownText,
    this.detailsText,
    this.itemId,
    this.metadata = const <String, Object?>{},
  });

  factory CodexTimelineCell.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('Timeline cell has no id.');
    }
    final created = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return CodexTimelineCell(
      id: id,
      kind: _kind(json['kind']?.toString()),
      status: _status(json['status']?.toString()),
      createdAt:
          (created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
              .toUtc(),
      updatedAt:
          (updated ??
                  created ??
                  DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
              .toUtc(),
      turnId: _string(json['turnId']),
      isStreaming: json['isStreaming'] == true,
      isCollapsed: json['isCollapsed'] == true,
      title: _string(json['title']),
      subtitle: _string(json['subtitle']),
      markdownText: _string(json['markdownText']),
      renderedMarkdownText: _string(json['renderedMarkdownText']),
      detailsText: _string(json['detailsText']),
      itemId: _string(json['itemId']),
      metadata: _map(json['metadata']),
    );
  }

  final String id;
  final String? turnId;
  final CodexTimelineKind kind;
  final CodexTimelineStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isStreaming;
  final bool isCollapsed;
  final String? title;
  final String? subtitle;
  final String? markdownText;
  final String? renderedMarkdownText;
  final String? detailsText;
  final String? itemId;
  final Map<String, Object?> metadata;

  CodexTimelineCell copyWith({
    CodexTimelineKind? kind,
    CodexTimelineStatus? status,
    DateTime? updatedAt,
    bool? isStreaming,
    bool? isCollapsed,
    String? title,
    String? subtitle,
    String? markdownText,
    String? renderedMarkdownText,
    String? detailsText,
    String? itemId,
    Map<String, Object?>? metadata,
  }) => CodexTimelineCell(
    id: id,
    turnId: turnId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isStreaming: isStreaming ?? this.isStreaming,
    isCollapsed: isCollapsed ?? this.isCollapsed,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    markdownText: markdownText ?? this.markdownText,
    renderedMarkdownText: renderedMarkdownText ?? this.renderedMarkdownText,
    detailsText: detailsText ?? this.detailsText,
    itemId: itemId ?? this.itemId,
    metadata: metadata ?? this.metadata,
  );

  Map<String, Object?> toJson() => <String, Object?>{
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
    'renderedMarkdownText': renderedMarkdownText,
    'detailsText': detailsText,
    'itemId': itemId,
    'metadata': metadata,
  };
}

CodexTimelineKind _kind(String? value) {
  for (final kind in CodexTimelineKind.values) {
    if (kind.name == value) return kind;
  }
  return CodexTimelineKind.systemNotice;
}

CodexTimelineStatus _status(String? value) {
  for (final status in CodexTimelineStatus.values) {
    if (status.name == value) return status;
  }
  return CodexTimelineStatus.info;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

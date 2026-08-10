part of 'codex_timeline.dart';

CodexTimelineCell _newCell({
  required String id,
  required CodexTimelineKind kind,
  required CodexTimelineStatus status,
  required DateTime timestamp,
  String? turnId,
  String? itemId,
  String? title,
  String? subtitle,
  String? markdownText,
  String? detailsText,
  bool isStreaming = false,
  Map<String, Object?> metadata = const <String, Object?>{},
}) => CodexTimelineCell(
  id: id,
  turnId: turnId,
  itemId: itemId,
  kind: kind,
  status: status,
  createdAt: timestamp,
  updatedAt: timestamp,
  title: title,
  subtitle: subtitle,
  markdownText: markdownText,
  renderedMarkdownText: markdownText,
  detailsText: detailsText,
  isStreaming: isStreaming,
  metadata: metadata,
);

List<CodexTimelineCell> _upsert(
  List<CodexTimelineCell> cells,
  CodexTimelineCell next,
) {
  final index = cells.indexWhere((cell) => cell.id == next.id);
  if (index < 0) return <CodexTimelineCell>[...cells, next];
  final result = <CodexTimelineCell>[...cells];
  result[index] = CodexTimelineCell(
    id: next.id,
    turnId: next.turnId ?? result[index].turnId,
    kind: next.kind,
    status: next.status,
    createdAt: result[index].createdAt,
    updatedAt: next.updatedAt,
    isStreaming: next.isStreaming,
    // Server snapshots carry the reducer's default value (false). Keep a
    // user's local collapse choice when a later delta updates the same item.
    isCollapsed: next.isCollapsed || result[index].isCollapsed,
    title: next.title ?? result[index].title,
    subtitle: next.subtitle ?? result[index].subtitle,
    markdownText: next.markdownText ?? result[index].markdownText,
    renderedMarkdownText:
        next.renderedMarkdownText ?? result[index].renderedMarkdownText,
    detailsText: next.detailsText ?? result[index].detailsText,
    itemId: next.itemId ?? result[index].itemId,
    metadata: <String, Object?>{...result[index].metadata, ...next.metadata},
  );
  return result;
}

CodexTimelineCell? _find(List<CodexTimelineCell> cells, String id) {
  for (final cell in cells) {
    if (cell.id == id) return cell;
  }
  return null;
}

CodexTimelineKind _kindFor(String type, String method) {
  if (type.contains('usermessage') || type.contains('user_message')) {
    return CodexTimelineKind.userMessage;
  }
  if (type.contains('agentmessage') || type.contains('assistant')) {
    return CodexTimelineKind.assistantMessage;
  }
  if (type.contains('reason')) return CodexTimelineKind.reasoning;
  if (type.contains('filechange') ||
      type.contains('diff') ||
      method.contains('filechange')) {
    return CodexTimelineKind.diff;
  }
  if (type.contains('command') || method.contains('commandexecution')) {
    return CodexTimelineKind.command;
  }
  if (type.contains('subagent') ||
      type.contains('collab') ||
      method.contains('subagent') ||
      method.contains('collab')) {
    return CodexTimelineKind.subAgent;
  }
  if (type.contains('plan') || method.contains('/plan')) {
    return CodexTimelineKind.plan;
  }
  if (type.contains('websearch') ||
      type.contains('dynamictool') ||
      type.contains('imageview') ||
      type.contains('imagegeneration') ||
      type.contains('sleep') ||
      type.contains('contextcompaction') ||
      type.contains('enteredreview') ||
      type.contains('exitedreview') ||
      type.contains('extension')) {
    return CodexTimelineKind.toolCall;
  }
  if (type.contains('tool') ||
      method.contains('tool') ||
      method.contains('outputdelta')) {
    return CodexTimelineKind.toolCall;
  }
  return CodexTimelineKind.progressText;
}

String _titleFor(
  String type,
  String method, {
  Map<String, Object?> item = const <String, Object?>{},
}) {
  if (type.contains('contextcompaction')) {
    return method.contains('completed') ? 'Compacted' : 'Compacting';
  }
  final explicit = _firstString(<Object?>[
    item['title'],
    item['name'],
    item['tool'],
    item['command'],
  ]);
  if (explicit.isNotEmpty) return explicit;
  if (type.contains('command')) return 'Command';
  if (type.contains('filechange')) return 'File changes';
  if (type.contains('reason')) return 'Reasoning';
  if (type.contains('plan') || method.contains('/plan')) return 'Plan';
  if (type.contains('subagent') ||
      type.contains('collab') ||
      method.contains('subagent') ||
      method.contains('collab')) {
    return 'Sub-agent';
  }
  if (method.contains('review')) return 'Review';
  if (type.contains('websearch')) return 'Web search';
  if (type.contains('imageview')) return 'Viewed image';
  if (type.contains('imagegeneration')) return 'Generated image';
  if (type.contains('enteredreview')) return 'Entered review mode';
  if (type.contains('exitedreview')) return 'Exited review mode';
  if (type.contains('tool') || method.contains('tool')) return 'Tool call';
  return 'Codex activity';
}

String _contextCompactionTitle(CodexTimelineStatus status) => switch (status) {
  CodexTimelineStatus.failed => 'Compaction failed',
  CodexTimelineStatus.completed => 'Compacted',
  _ => 'Compacting',
};

List<CodexTimelineCell> _updateTurnSeparator(
  List<CodexTimelineCell> cells,
  String turnId,
  Map<String, Object?> params,
  DateTime completedAt,
) {
  if (turnId.isEmpty) return cells;
  final turn = _map(params['turn']);
  final index = cells.indexWhere(
    (cell) =>
        cell.kind == CodexTimelineKind.turnSeparator && cell.turnId == turnId,
  );
  if (index < 0) return cells;
  final separator = cells[index];
  final explicitDuration = turn['durationMs'];
  final duration = explicitDuration is num
      ? explicitDuration.toInt()
      : completedAt
            .difference(separator.createdAt)
            .inMilliseconds
            .clamp(0, 1 << 53);
  final next = <CodexTimelineCell>[...cells];
  next[index] = separator.copyWith(
    updatedAt: completedAt,
    metadata: <String, Object?>{
      ...separator.metadata,
      'startedAt': turn['startedAt'] ?? separator.metadata['startedAt'],
      'completedAt': turn['completedAt'],
      'computedDurationMs': duration,
    },
  );
  return next;
}

String _itemMarkdown(Map<String, Object?> item) {
  final direct = _firstString(<Object?>[item['text'], item['message']]);
  if (direct.isNotEmpty) return direct;
  for (final key in <String>['summary', 'content', 'fragments']) {
    final values = item[key];
    if (values is! List) continue;
    final parts = <String>[];
    for (final value in values) {
      if (value is String && value.isNotEmpty) {
        parts.add(value);
      } else if (value is Map) {
        final text = value['text'];
        if (text is String && text.isNotEmpty) parts.add(text);
      }
    }
    if (parts.isNotEmpty) return parts.join('\n');
  }
  return _firstString(<Object?>[item['review']]);
}

String _itemDetails(Map<String, Object?> item) {
  for (final key in <String>[
    'aggregatedOutput',
    'output',
    'result',
    'error',
    'diff',
    'commandOutput',
    'changes',
    'contentItems',
    'action',
  ]) {
    final value = item[key];
    if (value == null) continue;
    if (value is String) {
      if (value.isNotEmpty) return value;
    } else {
      return value.toString();
    }
  }
  return '';
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num) return value.toString();
  }
  return '';
}

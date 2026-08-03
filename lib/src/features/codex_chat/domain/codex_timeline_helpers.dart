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
    isCollapsed: next.isCollapsed,
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
  final explicit = _firstString(<Object?>[
    item['title'],
    item['name'],
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
  if (type.contains('tool') || method.contains('tool')) return 'Tool call';
  return 'Codex activity';
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

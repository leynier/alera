import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// The verb a "Worked for" row uses for an activity item.
enum AgentChatWorkedActionKind {
  review,
  edit,
  read,
  viewImage,
  listFiles,
  search,
  webSearch,
  delegate,
  tool,
  ran,
}

class const AgentChatWorkedAction({
  required final AgentChatItem item,
  required final AgentChatWorkedActionKind kind,
  required final String label,
  final int count = 1,
}) {
  factory fromItem(AgentChatItem item) {
    final kind = agentChatWorkedActionKind(item);
    return AgentChatWorkedAction(
      item: item,
      kind: kind,
      label: _label(item, kind),
      count: kind == AgentChatWorkedActionKind.edit && item.changes.length > 1
          ? item.changes.length
          : 1,
    );
  }
}

AgentChatWorkedActionKind agentChatWorkedActionKind(AgentChatItem item) {
  switch (item.type) {
    case AgentChatItemType.fileChange:
      return AgentChatWorkedActionKind.edit;
    case AgentChatItemType.webSearch:
      return AgentChatWorkedActionKind.webSearch;
    case AgentChatItemType.imageView:
      return AgentChatWorkedActionKind.viewImage;
    case AgentChatItemType.reviewEntered || AgentChatItemType.reviewExited:
      return AgentChatWorkedActionKind.review;
    case AgentChatItemType.collabAgentToolCall:
      return AgentChatWorkedActionKind.delegate;
    case AgentChatItemType.commandExecution:
      return _commandActionKind(item) ?? AgentChatWorkedActionKind.ran;
    case AgentChatItemType.mcpToolCall || AgentChatItemType.dynamicToolCall:
      return _toolActionKind(item.toolName ?? item.title);
    default:
      return AgentChatWorkedActionKind.tool;
  }
}

// Codex annotates commands with what they did; other providers do not, and
// their commands simply "ran".
AgentChatWorkedActionKind? _commandActionKind(AgentChatItem item) {
  final actions = agentChatJsonList(item.data['commandActions']);
  final types = <String>{
    for (final action in actions)
      agentChatWireToken(agentChatJsonMap(action)['type']),
  };
  if (types.contains('search')) return AgentChatWorkedActionKind.search;
  if (types.contains('read')) return AgentChatWorkedActionKind.read;
  if (types.contains('listfiles')) return AgentChatWorkedActionKind.listFiles;
  return null;
}

// File tools are named alike across agents (Read, Grep, Glob, LS, view...).
AgentChatWorkedActionKind _toolActionKind(String? name) {
  final tool = agentChatWireToken(name);
  if (tool.isEmpty) return AgentChatWorkedActionKind.tool;
  if (tool == 'read' || tool == 'view' || tool == 'readfile') {
    return AgentChatWorkedActionKind.read;
  }
  if (tool == 'grep' || tool == 'glob' || tool == 'search' || tool == 'find') {
    return AgentChatWorkedActionKind.search;
  }
  if (tool == 'ls' || tool == 'list' || tool == 'listfiles') {
    return AgentChatWorkedActionKind.listFiles;
  }
  if (tool.contains('websearch') || tool.contains('webfetch')) {
    return AgentChatWorkedActionKind.webSearch;
  }
  return AgentChatWorkedActionKind.tool;
}

String _label(AgentChatItem item, AgentChatWorkedActionKind kind) {
  final target = _target(item);
  return switch (kind) {
    AgentChatWorkedActionKind.review =>
      item.type == AgentChatItemType.reviewEntered
          ? 'Entered review mode'
          : 'Exited review mode',
    AgentChatWorkedActionKind.edit => _editLabel(item),
    AgentChatWorkedActionKind.read =>
      target == null ? 'Read a file' : 'Read ${_basename(target)}',
    AgentChatWorkedActionKind.viewImage =>
      target == null ? 'Viewed an image' : 'Viewed ${_basename(target)}',
    AgentChatWorkedActionKind.listFiles =>
      target == null ? 'Listed files' : 'Listed files in $target',
    AgentChatWorkedActionKind.search =>
      item.query != null
          ? 'Searched for ${item.query}'
          : 'Searched with ${item.command ?? item.toolName ?? 'a tool'}',
    AgentChatWorkedActionKind.webSearch =>
      item.query == null
          ? 'Searched the web'
          : 'Searched the web for ${item.query}',
    AgentChatWorkedActionKind.delegate =>
      'Delegated to ${item.agentId ?? item.title ?? 'an agent'}',
    AgentChatWorkedActionKind.tool =>
      'Used ${item.toolName ?? item.title ?? 'a tool'}',
    AgentChatWorkedActionKind.ran =>
      'Ran ${item.command ?? item.title ?? 'a command'}',
  };
}

String? _target(AgentChatItem item) {
  final input = agentChatJsonMap(item.input);
  return item.imagePath ??
      agentChatJsonString(input['path']) ??
      agentChatJsonString(input['file_path']) ??
      agentChatJsonString(input['filePath']) ??
      item.title;
}

String _editLabel(AgentChatItem item) {
  final changes = item.changes;
  if (changes.length != 1) {
    return changes.isEmpty ? 'Edited files' : 'Edited ${changes.length} files';
  }
  final change = changes.single;
  final counts = change.lineCounts;
  final suffix = counts.additions == 0 && counts.deletions == 0
      ? ''
      : ' +${counts.additions} -${counts.deletions}';
  final name = change.path.isEmpty ? 'a file' : _basename(change.path);
  return 'Edited $name$suffix';
}

String _basename(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  final separator = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  return separator < 0 ? trimmed : trimmed.substring(separator + 1);
}

/// "Ran 3 commands, edited 2 files" for a group of actions.
String agentChatWorkedSummary(List<AgentChatWorkedAction> actions) {
  final counts = <AgentChatWorkedActionKind, int>{};
  for (final action in actions) {
    counts.update(
      action.kind,
      (count) => count + action.count,
      ifAbsent: () => action.count,
    );
  }
  final parts = <String>[
    for (final kind in AgentChatWorkedActionKind.values)
      if (counts[kind] case final int count) _summaryPart(kind, count, actions),
  ];
  if (parts.isEmpty) return 'Worked';
  final summary = parts.join(', ');
  return '${summary[0].toUpperCase()}${summary.substring(1)}';
}

String _summaryPart(
  AgentChatWorkedActionKind kind,
  int count,
  List<AgentChatWorkedAction> actions,
) {
  String plural(String one, String many) => count == 1 ? one : many;
  return switch (kind) {
    AgentChatWorkedActionKind.review =>
      count == 1
          ? actions
                .firstWhere((action) => action.kind == kind)
                .label
                .toLowerCase()
          : 'changed review mode $count times',
    AgentChatWorkedActionKind.edit =>
      'edited $count ${plural('file', 'files')}',
    AgentChatWorkedActionKind.read => 'read $count ${plural('file', 'files')}',
    AgentChatWorkedActionKind.viewImage =>
      'viewed $count ${plural('image', 'images')}',
    AgentChatWorkedActionKind.listFiles =>
      'listed files $count ${plural('time', 'times')}',
    AgentChatWorkedActionKind.search =>
      'searched $count ${plural('time', 'times')}',
    AgentChatWorkedActionKind.webSearch =>
      'searched the web $count ${plural('time', 'times')}',
    AgentChatWorkedActionKind.delegate =>
      'delegated $count ${plural('task', 'tasks')}',
    AgentChatWorkedActionKind.tool => 'used $count ${plural('tool', 'tools')}',
    AgentChatWorkedActionKind.ran =>
      'ran $count ${plural('command', 'commands')}',
  };
}

/// "4s", "1m 5s", "2h 3m" for a turn's working time.
String agentChatDurationLabel(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds < 1 ? 1 : seconds}s';
  final minutes = duration.inMinutes;
  if (minutes < 60) {
    final rest = seconds - minutes * 60;
    return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  }
  final hours = duration.inHours;
  final rest = minutes - hours * 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

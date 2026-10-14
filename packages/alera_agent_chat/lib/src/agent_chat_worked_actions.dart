import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_subagent.dart';

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
  if (item.startsSubagent) return AgentChatWorkedActionKind.delegate;
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

String _label(AgentChatItem item, AgentChatWorkedActionKind kind) =>
    _phrase(item, kind, live: false);

/// The present-tense label of an action a running turn is busy with:
/// "Running make test", "Reading main.dart".
String agentChatWorkedActionLiveLabel(AgentChatWorkedAction action) =>
    _phrase(action.item, action.kind, live: true);

String _phrase(
  AgentChatItem item,
  AgentChatWorkedActionKind kind, {
  required bool live,
}) {
  final target = _target(item);
  String verb(String past, String present) => live ? present : past;
  return switch (kind) {
    AgentChatWorkedActionKind.review =>
      item.type == AgentChatItemType.reviewEntered
          ? '${verb('Entered', 'Entering')} review mode'
          : '${verb('Exited', 'Exiting')} review mode',
    AgentChatWorkedActionKind.edit => _editLabel(item, live: live),
    AgentChatWorkedActionKind.read =>
      '${verb('Read', 'Reading')} '
          '${target == null ? 'a file' : _basename(target)}',
    AgentChatWorkedActionKind.viewImage =>
      '${verb('Viewed', 'Viewing')} '
          '${target == null ? 'an image' : _basename(target)}',
    AgentChatWorkedActionKind.listFiles =>
      target == null
          ? '${verb('Listed', 'Listing')} files'
          : '${verb('Listed', 'Listing')} files in $target',
    AgentChatWorkedActionKind.search =>
      item.query != null
          ? '${verb('Searched', 'Searching')} for ${item.query}'
          : '${verb('Searched', 'Searching')} with '
                '${item.command ?? item.toolName ?? 'a tool'}',
    AgentChatWorkedActionKind.webSearch =>
      item.query == null
          ? '${verb('Searched', 'Searching')} the web'
          : '${verb('Searched', 'Searching')} the web for ${item.query}',
    AgentChatWorkedActionKind.delegate =>
      item.startsSubagent
          ? '${verb('Ran', 'Running')} sub-agent: ${item.subagentLabel}'
          : '${verb('Delegated', 'Delegating')} to '
                '${item.agentId ?? item.title ?? 'an agent'}',
    AgentChatWorkedActionKind.tool =>
      '${verb('Used', 'Using')} ${item.toolName ?? item.title ?? 'a tool'}',
    AgentChatWorkedActionKind.ran =>
      '${verb('Ran', 'Running')} ${item.command ?? item.title ?? 'a command'}',
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

String _editLabel(AgentChatItem item, {required bool live}) {
  final verb = live ? 'Editing' : 'Edited';
  final changes = item.changes;
  if (changes.length != 1) {
    return changes.isEmpty ? '$verb files' : '$verb ${changes.length} files';
  }
  final change = changes.single;
  final counts = change.lineCounts;
  final suffix = live || (counts.additions == 0 && counts.deletions == 0)
      ? ''
      : ' +${counts.additions} -${counts.deletions}';
  final name = change.path.isEmpty ? 'a file' : _basename(change.path);
  return '$verb $name$suffix';
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

/// The label of a reasoning row: the provider's title, else "Thinking" while
/// the agent reasons and "Thought" once it is done.
String agentChatReasoningLabel(AgentChatItem item) {
  final title = item.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return item.isInProgress ? 'Thinking' : 'Thought';
}

/// The first sentence of [text], flattened to one line and clamped to
/// [maxLength] characters, for the live row of a running turn. A leading
/// markdown heading or bold title line counts as the sentence.
String? agentChatReasoningSnippet(String text, {int maxLength = 140}) {
  String? line;
  for (final candidate in text.split('\n')) {
    final cleaned = candidate
        .replaceFirst(RegExp(r'^\s*(#+|>)\s*'), '')
        .replaceAll(RegExp(r'\*\*|__|`'), '')
        .trim();
    if (cleaned.isNotEmpty) {
      line = cleaned;
      break;
    }
  }
  if (line == null) return null;
  final flat = line.replaceAll(RegExp(r'\s+'), ' ');
  final end = RegExp(r'[.!?](\s|$)').firstMatch(flat);
  final sentence = end == null ? flat : flat.substring(0, end.start + 1);
  if (sentence.length <= maxLength) return sentence;
  return '${sentence.substring(0, maxLength - 1).trimRight()}\u2026';
}

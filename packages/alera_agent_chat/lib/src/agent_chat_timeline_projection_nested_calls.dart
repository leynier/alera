part of 'agent_chat_timeline_projection.dart';

/// An action row's item that is not a sub-agent's call.
bool _isPlainAction(AgentChatItem item) =>
    item.type.isActivity &&
    item.type != AgentChatItemType.unknown &&
    !item.startsSubagent;

/// The calls each ordinary call made through itself (a Pi codemode script
/// calling tools), in timeline order, keyed by the caller's id. A sub-agent's
/// call keeps its work as a sub-agent; only callers present in [items] take
/// nested calls, so a call whose caller is missing stays in the main flow.
Map<String, List<AgentChatItem>> _nestedCalls(List<AgentChatItem> items) {
  final callers = <String, AgentChatItem>{
    for (final item in items)
      if (_isPlainAction(item)) item.id: item,
  };
  if (callers.isEmpty) return const <String, List<AgentChatItem>>{};
  // A chain of callers that loops back has no row to hang from.
  bool reachesTop(AgentChatItem item) {
    final seen = <String>{item.id};
    for (
      var parent = item.parentItemId;
      parent != null && callers.containsKey(parent);
      parent = callers[parent]!.parentItemId
    ) {
      if (!seen.add(parent)) return false;
    }
    return true;
  }

  final nested = <String, List<AgentChatItem>>{};
  for (final item in items) {
    final parent = item.parentItemId;
    if (parent != null &&
        callers.containsKey(parent) &&
        _isPlainAction(item) &&
        reachesTop(item)) {
      nested.putIfAbsent(parent, () => <AgentChatItem>[]).add(item);
    }
  }
  return nested;
}

/// [item] as an action, with the calls it made under it at any depth.
AgentChatWorkedAction _actionWithNested(
  AgentChatItem item,
  Map<String, List<AgentChatItem>> nested,
) => AgentChatWorkedAction.fromItem(
  item,
  nested: List<AgentChatWorkedAction>.unmodifiable(<AgentChatWorkedAction>[
    for (final call in nested[item.id] ?? const <AgentChatItem>[])
      _actionWithNested(call, nested),
  ]),
);

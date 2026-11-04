part of 'agent_chat_timeline_projection.dart';

/// A provider-native sub-agent under the call that started it, with the
/// sub-agent's own work folded the way the main agent's is.
final class AgentChatSubagentRow extends AgentChatActivityRow {
  AgentChatSubagentRow(this.call, this.rows, {required this.childCount})
    : label = call.subagentLabel,
      status = call.subagentStatus,
      summary = call.subagent?.summary;

  final AgentChatItem call;
  final List<AgentChatActivityRow> rows;
  final int childCount;
  final String label;
  final AgentChatSubagentStatus status;
  final String? summary;

  @override
  String get key => 'subagent-${call.id}';

  bool get streaming => status == AgentChatSubagentStatus.running;
}

/// Each sub-agent call's items, in timeline order, keyed by the call's id.
/// Only calls present in the turn take children; an item whose call is
/// missing stays in the main flow.
Map<String, List<AgentChatItem>> _subagentChildren(List<AgentChatItem> items) {
  final calls = <String>{
    for (final item in items)
      if (item.startsSubagent) item.id,
  };
  if (calls.isEmpty) return const <String, List<AgentChatItem>>{};
  final children = <String, List<AgentChatItem>>{};
  for (final item in items) {
    final parent = item.parentItemId;
    if (parent != null && parent != item.id && calls.contains(parent)) {
      children.putIfAbsent(parent, () => <AgentChatItem>[]).add(item);
    }
  }
  return children;
}

part of 'agent_chat_timeline_projection.dart';

/// `agentChat.subagent`: the call that started a provider-native sub-agent
/// and the items under it, oldest first.
final class AgentChatSubagentTranscript {
  const AgentChatSubagentTranscript({
    required this.call,
    required this.items,
    this.truncated = false,
  });

  factory AgentChatSubagentTranscript.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatSubagentTranscript(
      call: AgentChatItem.fromJson(json['call']),
      items: <AgentChatItem>[
        for (final item in agentChatJsonList(json['items']))
          if (item is Map) AgentChatItem.fromJson(item),
      ],
      truncated: agentChatJsonBool(json['truncated']),
    );
  }

  final AgentChatItem call;
  final List<AgentChatItem> items;

  /// The runtime scanned its bound of the chat's latest rows before it
  /// reached the call, so older work may be missing.
  final bool truncated;
}

/// The items under [callId] at any depth, in the order given. Continuation
/// rows (`<id>:segment:...`) follow the item they continue. Mirrors the
/// runtime's `subagent_descendants`, so a live view and a read agree.
List<AgentChatItem> agentChatSubagentDescendants(
  Iterable<AgentChatItem> items,
  String callId,
) {
  final parents = <String, String>{
    for (final item in items)
      if (item.parentItemId case final parent?) item.id: parent,
  };
  final included = <String>{};
  for (final item in items) {
    var current = item.id;
    final seen = <String>{};
    for (
      var parent = parents[current];
      parent != null;
      parent = parents[current]
    ) {
      if (parent == callId) {
        included.add(item.id);
        break;
      }
      if (!seen.add(parent)) break;
      current = parent;
    }
  }
  return <AgentChatItem>[
    for (final item in items)
      if (included.contains(item.id) ||
          included.contains(item.id.split(':segment:').first))
        item,
  ];
}

/// "Working 1m 5s", "Completed in 42s", "Failed", "Stopped": the sub-agent
/// bar's status, live from [now] while the sub-agent runs.
String agentChatSubagentStatusLabel(AgentChatItem call, DateTime now) {
  final status = call.subagentStatus;
  final startedAt = call.subagent?.startedAt;
  return switch (status) {
    AgentChatSubagentStatus.running when startedAt == null => 'Working',
    AgentChatSubagentStatus.running =>
      'Working ${agentChatDurationLabel(_elapsed(startedAt!, now))}',
    AgentChatSubagentStatus.completed => switch ((
      startedAt,
      call.subagent?.completedAt,
    )) {
      (final start?, final end?) when !end.isBefore(start) =>
        'Completed in ${agentChatDurationLabel(end.difference(start))}',
      _ => 'Completed',
    },
    AgentChatSubagentStatus.failed => 'Failed',
    AgentChatSubagentStatus.stopped => 'Stopped',
  };
}

/// A provider-native sub-agent shown on its own: what it was asked, its work
/// folded the way the main agent's is, and its own sub-agents as rows that
/// open in turn. Built from the call and its descendants, live from the
/// chat's thread or from an `agentChat.subagent` read.
final class AgentChatSubagentTimeline {
  AgentChatSubagentTimeline._(this.call, this.rows, this.itemCount);

  factory AgentChatSubagentTimeline.build(
    AgentChatItem call,
    List<AgentChatItem> descendants,
  ) {
    final joined = AgentChatContinuationProjection.build(descendants).items;
    final direct = <AgentChatItem>[
      for (final item in joined)
        if (item.parentItemId == call.id) item,
    ];
    return AgentChatSubagentTimeline._(
      call,
      List<AgentChatActivityRow>.unmodifiable(
        _activityRows(direct, _subagentChildren(joined)),
      ),
      joined.length,
    );
  }

  final AgentChatItem call;
  final List<AgentChatActivityRow> rows;
  final int itemCount;

  String get label => call.subagentLabel;

  String? get prompt => call.subagentPrompt;

  String? get summary => call.subagent?.summary;

  bool get running => call.subagentStatus == AgentChatSubagentStatus.running;
}

/// Every call in [items] that started a provider-native sub-agent, oldest
/// first, for the relationships control.
List<AgentChatItem> agentChatSubagentCalls(Iterable<AgentChatItem> items) =>
    <AgentChatItem>[
      for (final item in items)
        if (item.startsSubagent) item,
    ];

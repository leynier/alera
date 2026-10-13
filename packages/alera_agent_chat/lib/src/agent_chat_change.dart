import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_queue_entry.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

/// Which text field of an item a streamed append extends.
enum AgentChatTextStream {
  text,
  reasoningText,
  output;

  static AgentChatTextStream fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'text' => AgentChatTextStream.text,
        'reasoningtext' => AgentChatTextStream.reasoningText,
        _ => AgentChatTextStream.output,
      };
}

/// Appends [text] to an item's [stream] at [offset], measured in UTF-16 code
/// units of the field before the append. The offset makes a replayed append
/// idempotent and a missed one detectable.
class const AgentChatTextAppend({
  required final String itemId,
  required final AgentChatTextStream stream,
  required final int offset,
  required final String text,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTextAppend(
      itemId: agentChatJsonText(json['itemId']),
      stream: AgentChatTextStream.fromJson(json['stream']),
      offset: agentChatJsonInt(json['offset']) ?? -1,
      text: agentChatJsonText(json['text']),
    );
  }
}

/// One `agentChatChanged` event. Absent fields are unchanged; for nullable
/// fields the `has*` flags distinguish "unchanged" from "cleared".
class const AgentChatChange({
  required final String chatId,
  required final int cursor,
  final String workspaceId = '',
  final List<AgentChatItem> items = const <AgentChatItem>[],
  final List<String> removedItemIds = const <String>[],
  final List<AgentChatTextAppend> textAppends = const <AgentChatTextAppend>[],
  final List<AgentChatTurn> turns = const <AgentChatTurn>[],
  final List<AgentChatRequest>? requests,
  final List<AgentChatQueueEntry>? queue,
  final AgentChatSession? session,
  final AgentChatUsage? usage,
  final String? title,
  final String? provider,
  final String? providerInstanceId,
  final bool? archived,
  final bool hasRecovery = false,
  final AgentChatRecovery? recovery,
}) {
  /// Parses the event payload `{chatId, workspaceId, cursor, delta}`.
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final delta = agentChatJsonMap(json['delta']);
    final recovery = delta['recovery'];
    return AgentChatChange(
      chatId: agentChatJsonText(json['chatId']),
      workspaceId: agentChatJsonText(json['workspaceId']),
      cursor: agentChatJsonInt(json['cursor']) ?? -1,
      items: agentChatItemsFromJson(delta['items']),
      removedItemIds: agentChatJsonStringList(delta['removedItemIds']),
      textAppends: <AgentChatTextAppend>[
        for (final append in agentChatJsonList(delta['textAppends']))
          AgentChatTextAppend.fromJson(append),
      ],
      turns: agentChatTurnsFromJson(delta['turns']),
      requests: delta.containsKey('requests')
          ? agentChatRequestsFromJson(delta['requests'])
          : null,
      queue: delta.containsKey('queue')
          ? agentChatQueueFromJson(delta['queue'])
          : null,
      session: delta['session'] is Map
          ? AgentChatSession.fromJson(delta['session'])
          : null,
      usage: delta['usage'] is Map
          ? AgentChatUsage.fromJson(delta['usage'])
          : null,
      title: delta['title'] is String ? delta['title']! as String : null,
      provider: agentChatJsonString(delta['provider']),
      providerInstanceId: agentChatJsonString(delta['providerInstanceId']),
      archived: delta['archived'] is bool ? delta['archived']! as bool : null,
      hasRecovery: delta.containsKey('recovery'),
      recovery: recovery is Map ? AgentChatRecovery.fromJson(recovery) : null,
    );
  }
}

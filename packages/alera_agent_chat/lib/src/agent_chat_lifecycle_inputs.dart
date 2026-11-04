import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

/// A queue entry and the exact live turn it must steer in one host operation.
class const AgentChatQueueSteerInput({
  required final String chatId,
  required final String workspaceId,
  required final String requestId,
  required final String queueId,
  required final String turnId,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'chatId': chatId,
    'workspaceId': workspaceId,
    'requestId': requestId,
    'queueId': queueId,
    'turnId': turnId,
  };
}

class const AgentChatCloseResult({
  required final bool archived,
  final bool discarded = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final discarded = agentChatJsonBool(json['discarded']);
    return AgentChatCloseResult(
      archived: agentChatJsonBool(json['archived'], !discarded),
      discarded: discarded,
    );
  }
}

class const AgentChatRewindResult({
  required final AgentChatSnapshot snapshot,
  required final String prompt,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  final bool? filesystemChangesReverted = false,
  final bool filesystemRewindAcknowledged = false,
}) {
  factory fromJson(
    Object? value, {
    AgentChatRewindMode mode = AgentChatRewindMode.transcript,
  }) {
    final json = agentChatJsonMap(value);
    return AgentChatRewindResult(
      snapshot: AgentChatSnapshot.fromJson(json['snapshot']),
      prompt: agentChatJsonText(json['prompt']),
      attachments: List.unmodifiableOf(<AgentChatAttachment>[
        for (final attachment in agentChatJsonList(json['attachments']))
          if (attachment is Map) AgentChatAttachment.fromJson(attachment),
      ]),
      filesystemChangesReverted: json.containsKey('filesystemChangesReverted')
          ? agentChatFilesystemEffectFromJson(json['filesystemChangesReverted'])
          : mode == AgentChatRewindMode.transcript
          ? false
          : null,
      filesystemRewindAcknowledged: agentChatJsonBool(
        json['filesystemRewindAcknowledged'],
      ),
    );
  }
}

class const AgentChatApprovalHistoryPage({
  final List<AgentChatItem> items = const <AgentChatItem>[],
  final String? historyBefore,
  final bool scanLimited = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatApprovalHistoryPage(
      items: List.unmodifiableOf(agentChatItemsFromJson(json['items'])),
      historyBefore: agentChatJsonString(json['historyBefore']),
      scanLimited: agentChatJsonBool(json['scanLimited']),
    );
  }
}

class const AgentChatTurnDiffItem({
  required final String itemId,
  required final String status,
  final List<AgentChatJson> changes = const <AgentChatJson>[],
  final String? diff,
  final AgentChatJson? payloadRef,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTurnDiffItem(
      itemId: agentChatJsonText(json['itemId']),
      status: agentChatJsonText(json['status']),
      changes: List.unmodifiableOf(<AgentChatJson>[
        for (final change in agentChatJsonList(json['changes']))
          if (change is Map) Map.unmodifiableOf(agentChatJsonMap(change)),
      ]),
      diff: agentChatJsonString(json['diff']),
      payloadRef: json['payloadRef'] is Map
          ? Map.unmodifiableOf(agentChatJsonMap(json['payloadRef']))
          : null,
    );
  }
}

/// Provider-reported changes; an unavailable report never implies a clean tree.
class const AgentChatTurnDiff({
  required final String turnId,
  final String source = 'provider',
  final bool available = false,
  final List<AgentChatTurnDiffItem> items = const <AgentChatTurnDiffItem>[],
  final bool truncated = false,
  final String? reason,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTurnDiff(
      turnId: agentChatJsonText(json['turnId']),
      source: agentChatJsonString(json['source']) ?? 'provider',
      available: agentChatJsonBool(json['available']),
      items: List.unmodifiableOf(<AgentChatTurnDiffItem>[
        for (final item in agentChatJsonList(json['items']))
          if (item is Map) AgentChatTurnDiffItem.fromJson(item),
      ]),
      truncated: agentChatJsonBool(json['truncated']),
      reason: agentChatJsonString(json['reason']),
    );
  }
}

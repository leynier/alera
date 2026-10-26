import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// What moved context into a chat (`agentChatTransfersV1`), as T3 Code's
/// `OrchestrationV2ContextTransferType` names it.
enum AgentChatTransferKind {
  /// The source's history up to the fork point, copied into a fork.
  fork,

  /// The transcript carried into a fresh provider session of the same chat.
  providerHandoff,

  /// A fork's work handed back to the chat it was forked from.
  mergeBack,

  /// A delegated brief, sent to a child chat.
  subagentSpawn,

  /// A delegated chat's result, delivered to its parent.
  subagentResult,

  /// A kind a newer runtime added.
  unknown;

  static AgentChatTransferKind fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatTransferKind.values,
    AgentChatTransferKind.unknown,
  );

  /// The row's label, read in the chat that received the context.
  String get label => switch (this) {
    fork => 'Forked From',
    providerHandoff => 'Context Handoff',
    mergeBack => 'Merged Back From',
    subagentSpawn => 'Delegated By',
    subagentResult => 'Result From',
    unknown => 'Context From',
  };
}

enum AgentChatTransferStatus {
  pending,
  consumed,
  failed,
  superseded;

  static AgentChatTransferStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatTransferStatus.values,
    AgentChatTransferStatus.consumed,
  );
}

/// One record of context moved into a chat: where it came from, which turns
/// it joined and whether the receiving agent has it yet. Records live in the
/// receiving chat, so the source of a fork or merge-back is
/// [sourceChatId] and this chat is [targetChatId].
class const AgentChatContextTransfer({
  required final String id,
  required final AgentChatTransferKind kind,
  required final String sourceChatId,
  required final String targetChatId,
  required final AgentChatTransferStatus status,
  required final DateTime createdAt,
  final DateTime? updatedAt,
  final DateTime? consumedAt,
  final String? sourceTitle,
  final String? sourceTurnId,
  final String? targetTurnId,

  /// The receiving chat's item that shows the transfer (a merge-back notice
  /// or a handoff marker), when it has one.
  final String? itemId,
  final String? taskId,
  final AgentChatHandoffEndpoint? from,
  final AgentChatHandoffEndpoint? to,
  final String? error,
}) {
  static AgentChatContextTransfer? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['transferId']);
    final source = agentChatJsonString(json['sourceChatId']);
    final target = agentChatJsonString(json['targetChatId']);
    if (id == null || source == null || target == null) return null;
    return AgentChatContextTransfer(
      id: id,
      kind: AgentChatTransferKind.fromJson(json['kind']),
      sourceChatId: source,
      targetChatId: target,
      status: AgentChatTransferStatus.fromJson(json['status']),
      createdAt:
          agentChatJsonDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: agentChatJsonDate(json['updatedAt']),
      consumedAt: agentChatJsonDate(json['consumedAt']),
      sourceTitle: agentChatJsonString(json['sourceTitle']),
      sourceTurnId: agentChatJsonString(json['sourceTurnId']),
      targetTurnId: agentChatJsonString(json['targetTurnId']),
      itemId: agentChatJsonString(json['itemId']),
      taskId: agentChatJsonString(json['taskId']),
      from: AgentChatHandoffEndpoint.fromJson(json['from']),
      to: AgentChatHandoffEndpoint.fromJson(json['to']),
      error: agentChatJsonString(json['error']),
    );
  }

  /// Context that came from another chat, the only kind with a chat to open.
  bool get crossChat => sourceChatId != targetChatId;

  bool get failed => status == AgentChatTransferStatus.failed || error != null;

  /// "Pending", "Delivered" or "Failed", the status a row and its card show.
  String get statusLabel => switch (status) {
    _ when error != null => 'Failed',
    AgentChatTransferStatus.pending => switch (kind) {
      AgentChatTransferKind.mergeBack => 'Waiting for Next Message',
      _ => 'Pending',
    },
    AgentChatTransferStatus.consumed => 'Delivered',
    AgentChatTransferStatus.failed => 'Failed',
    AgentChatTransferStatus.superseded => 'Superseded',
  };
}

/// The records of a snapshot or delta, skipping malformed ones.
List<AgentChatContextTransfer> agentChatTransfersFromJson(Object? value) =>
    List<AgentChatContextTransfer>.unmodifiable(<AgentChatContextTransfer>[
      for (final entry in agentChatJsonList(value))
        ?AgentChatContextTransfer.tryParse(entry),
    ]);

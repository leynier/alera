import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_repository.dart';
import 'package:alera_agent_chat/src/runtime_agent_chat_native_history_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

final class RuntimeAgentChatLifecycleRepository
    extends AgentChatLifecycleRepository
    implements AgentChatNativeHistoryAccess {
  const RuntimeAgentChatLifecycleRepository(this._transport);

  final AgentChatTransport _transport;

  @override
  AgentChatNativeHistoryRepository get nativeHistory =>
      RuntimeAgentChatNativeHistoryRepository(_transport);

  @override
  Future<bool> supports(String capability) =>
      _transport.supportsCapability(capability);

  Future<AgentChatJson> _request(
    String capability,
    String verb,
    AgentChatJson payload,
  ) async {
    if (!await supports(capability))
      throw AgentChatCapabilityRequired(capability);
    return _transport.request(verb, payload);
  }

  AgentChatJson _scoped(AgentChatRef chat, AgentChatJson payload) =>
      <String, Object?>{
        'chatId': chat.chatId,
        'workspaceId': chat.workspaceId,
        ...payload,
      };

  @override
  Future<AgentChatCloseResult> close(
    AgentChatRef chat, {
    required String requestId,
  }) async => AgentChatCloseResult.fromJson(
    await _request(
      AgentChatWire.capability,
      AgentChatWire.close,
      _scoped(chat, <String, Object?>{'requestId': requestId}),
    ),
  );

  @override
  Future<int> markRead(
    AgentChatRef chat, {
    required String requestId,
    required int cursor,
  }) async {
    if (cursor < 0)
      throw const FormatException('A read cursor cannot be negative.');
    final json = await _request(
      AgentChatWire.readCursorCapability,
      AgentChatWire.markRead,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'cursor': cursor,
      }),
    );
    return agentChatJsonInt(json['readCursor'] ?? json['cursor']) ?? cursor;
  }

  @override
  Future<bool> queueEdit(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
    required String text,
  }) async {
    final json = await _request(
      AgentChatWire.queueEditCapability,
      AgentChatWire.queueEdit,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'queueId': queueId,
        'text': text,
      }),
    );
    // The runtime answers `{updated: true}`; `edited` is kept for any client
    // fake that still answers with the old key.
    return agentChatJsonBool(json['updated'] ?? json['edited']);
  }

  @override
  Future<bool> queueReorder(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
    required int index,
  }) async {
    if (index < 0) {
      throw const FormatException('A queue position cannot be negative.');
    }
    final json = await _request(
      AgentChatWire.queueReorderCapability,
      AgentChatWire.queueReorder,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'queueId': queueId,
        'index': index,
      }),
    );
    return agentChatJsonBool(json['reordered']);
  }

  @override
  Future<AgentChatSendResult> queueSteer(
    AgentChatQueueSteerInput input,
  ) async => AgentChatSendResult.fromJson(
    await _request(
      AgentChatWire.queueSteerCapability,
      AgentChatWire.queueSteer,
      input.toJson(),
    ),
  );

  @override
  Future<AgentChatOpenResult> fork(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
    String? title,
  }) async => AgentChatOpenResult.fromJson(
    await _request(
      AgentChatWire.forkCapability,
      AgentChatWire.fork,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'turnId': turnId,
        'title': ?title,
      }),
    ),
  );

  @override
  Future<AgentChatRewindResult> rewind(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
  }) async => AgentChatRewindResult.fromJson(
    await _request(
      AgentChatWire.rewindCapability,
      AgentChatWire.rewind,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'turnId': turnId,
      }),
    ),
  );

  @override
  Future<bool> delete(AgentChatRef chat, {required String requestId}) async {
    final json = await _request(
      AgentChatWire.deleteCapability,
      AgentChatWire.delete,
      _scoped(chat, <String, Object?>{'requestId': requestId}),
    );
    return agentChatJsonBool(json['deleted']);
  }

  @override
  Future<AgentChatApprovalHistoryPage> approvalHistory(
    AgentChatRef chat, {
    String? before,
    int? limit,
  }) async => AgentChatApprovalHistoryPage.fromJson(
    await _request(
      AgentChatWire.approvalHistoryCapability,
      AgentChatWire.approvalHistory,
      _scoped(chat, <String, Object?>{'before': ?before, 'limit': ?limit}),
    ),
  );

  @override
  Future<AgentChatTurnDiff> turnDiff(
    AgentChatRef chat, {
    required String turnId,
  }) async => AgentChatTurnDiff.fromJson(
    await _request(
      AgentChatWire.turnDiffCapability,
      AgentChatWire.turnDiff,
      _scoped(chat, <String, Object?>{'turnId': turnId}),
    ),
  );
}

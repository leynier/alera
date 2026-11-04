import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_native_operation.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

final class RuntimeAgentChatNativeHistoryRepository
    extends AgentChatNativeHistoryRepository {
  const RuntimeAgentChatNativeHistoryRepository(this._transport);

  final AgentChatTransport _transport;

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
  Future<AgentChatNativeOperation?> operation(
    AgentChatRef chat, {
    String? operationId,
  }) async {
    final json = await _request(
      AgentChatWire.nativeHistoryCapability,
      AgentChatWire.nativeHistoryOperation,
      _scoped(chat, <String, Object?>{'operationId': ?operationId}),
    );
    return agentChatPendingNativeOperationFromJson(json['operation']);
  }

  @override
  Future<AgentChatRewindResult> rewind(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
    AgentChatRewindMode mode = AgentChatRewindMode.transcript,
  }) async => AgentChatRewindResult.fromJson(
    await _request(
      mode == .native
          ? AgentChatWire.nativeRewindCapability
          : AgentChatWire.rewindCapability,
      AgentChatWire.rewind,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'turnId': turnId,
        if (mode != .transcript) 'mode': mode.wire,
      }),
    ),
    mode: mode,
  );

  @override
  Future<AgentChatFilesystemRewindResult> rewindFiles(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
  }) async => AgentChatFilesystemRewindResult.fromJson(
    await _request(
      AgentChatWire.rewindFilesCapability,
      AgentChatWire.rewindFiles,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'turnId': turnId,
      }),
    ),
  );

  @override
  Future<AgentChatSnapshot> configureFileCheckpoints(
    AgentChatRef chat, {
    required String requestId,
    required bool enabled,
  }) async {
    final json = await _request(
      AgentChatWire.fileCheckpointsCapability,
      AgentChatWire.fileCheckpointsConfigure,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'enabled': enabled,
      }),
    );
    return AgentChatSnapshot.fromJson(json['snapshot']);
  }

  @override
  Future<AgentChatNativeHistoryReconcileResult> reconcile(
    AgentChatRef chat, {
    required String requestId,
    required String operationId,
    required AgentChatNativeHistoryAction action,
    int? expectedRevision,
  }) async => AgentChatNativeHistoryReconcileResult.fromJson(
    await _request(
      AgentChatWire.nativeHistoryCapability,
      AgentChatWire.nativeHistoryReconcile,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'operationId': operationId,
        'action': action.wire,
        'expectedRevision': ?expectedRevision,
      }),
    ),
  );
}

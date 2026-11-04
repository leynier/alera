import 'package:alera_agent_chat/src/agent_chat_lifecycle_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_native_operation.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

/// Native history is an addon so existing lifecycle fakes keep their original
/// transcript-only rewind signature and semantics.
abstract class AgentChatNativeHistoryRepository {
  const AgentChatNativeHistoryRepository();

  Future<bool> supports(String capability) async => false;

  Future<AgentChatNativeOperation?> operation(
    AgentChatRef chat, {
    String? operationId,
  }) => Future.error(
    UnsupportedError('Native history operation status is unavailable.'),
  );

  Future<AgentChatRewindResult> rewind(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
    AgentChatRewindMode mode = AgentChatRewindMode.transcript,
  }) => Future.error(UnsupportedError('Native chat history is unavailable.'));

  Future<AgentChatFilesystemRewindResult> rewindFiles(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
  }) => Future.error(UnsupportedError('File rewind is unavailable.'));

  Future<AgentChatSnapshot> configureFileCheckpoints(
    AgentChatRef chat, {
    required String requestId,
    required bool enabled,
  }) => Future.error(UnsupportedError('File checkpointing is unavailable.'));

  Future<AgentChatNativeHistoryReconcileResult> reconcile(
    AgentChatRef chat, {
    required String requestId,
    required String operationId,
    required AgentChatNativeHistoryAction action,
    int? expectedRevision,
  }) => Future.error(
    UnsupportedError('Native history reconciliation is unavailable.'),
  );
}

final class UnsupportedAgentChatNativeHistoryRepository
    extends AgentChatNativeHistoryRepository {
  const UnsupportedAgentChatNativeHistoryRepository();
}

abstract interface class AgentChatNativeHistoryAccess {
  AgentChatNativeHistoryRepository get nativeHistory;
}

extension AgentChatNativeHistoryServices on AgentChatLifecycleRepository {
  AgentChatNativeHistoryRepository get nativeHistory =>
      this is AgentChatNativeHistoryAccess
      ? (this as AgentChatNativeHistoryAccess).nativeHistory
      : const UnsupportedAgentChatNativeHistoryRepository();
}

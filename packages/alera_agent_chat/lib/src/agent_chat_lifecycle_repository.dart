import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_skill.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_timeline_projection.dart';

abstract class AgentChatLifecycleRepository {
  const AgentChatLifecycleRepository();

  Future<bool> supports(String capability) async => false;

  Future<AgentChatCloseResult> close(
    AgentChatRef chat, {
    required String requestId,
  }) => Future.error(
    UnsupportedError('Chat lifecycle controls are unavailable.'),
  );

  Future<int> markRead(
    AgentChatRef chat, {
    required String requestId,
    required int cursor,
  }) => Future.error(UnsupportedError('Chat read state is unavailable.'));

  Future<bool> queueEdit(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
    required String text,
  }) =>
      Future.error(UnsupportedError('Queued message editing is unavailable.'));

  /// Moves a queued message to the zero-based [index]; `false` when it was
  /// already there.
  Future<bool> queueReorder(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
    required int index,
  }) => Future.error(
    UnsupportedError('Queued message reordering is unavailable.'),
  );

  Future<AgentChatSendResult> queueSteer(AgentChatQueueSteerInput input) =>
      Future.error(UnsupportedError('Queued message steering is unavailable.'));

  Future<AgentChatOpenResult> fork(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
    String? title,
  }) => Future.error(UnsupportedError('Chat forking is unavailable.'));

  Future<AgentChatRewindResult> rewind(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
  }) => Future.error(UnsupportedError('Chat rewind is unavailable.'));

  Future<bool> delete(AgentChatRef chat, {required String requestId}) =>
      Future.error(UnsupportedError('Chat deletion is unavailable.'));

  Future<AgentChatApprovalHistoryPage> approvalHistory(
    AgentChatRef chat, {
    String? before,
    int? limit,
  }) => Future.error(UnsupportedError('Approval history is unavailable.'));

  Future<AgentChatTurnDiff> turnDiff(
    AgentChatRef chat, {
    required String turnId,
  }) => Future.error(UnsupportedError('Turn diffs are unavailable.'));

  /// Uploads [chat]'s thread and the agent's logs to its vendor and returns
  /// the vendor's feedback id. Call it only after the person agreed to it.
  Future<String> feedback(
    AgentChatRef chat, {
    required String requestId,
    String? reason,
  }) => Future.error(UnsupportedError('Agent feedback is unavailable.'));

  /// What the composer's `$` menu offers for [chat]. [refresh] asks the
  /// runtime to discover them again instead of answering from its cache.
  Future<AgentChatSkillList> skills(
    AgentChatRef chat, {
    bool refresh = false,
  }) => Future.error(UnsupportedError('Agent skills are unavailable.'));

  /// A provider-native sub-agent's own transcript, by the call that started
  /// it (`agentChatSubagentThreadsV1`).
  Future<AgentChatSubagentTranscript> subagent(
    AgentChatRef chat, {
    required String itemId,
  }) =>
      Future.error(UnsupportedError('Sub-agent transcripts are unavailable.'));

  /// Stops the running sub-agent the call [itemId] started.
  Future<void> stopSubagent(
    AgentChatRef chat, {
    required String requestId,
    required String itemId,
  }) => Future.error(UnsupportedError('Stopping a sub-agent is unavailable.'));

  /// Hands this fork's work since the fork point to the chat it was forked
  /// from, for that chat's next turn (`agentChatMergeBackV1`). Answers the
  /// source chat's id.
  Future<String> mergeBack(AgentChatRef chat, {required String requestId}) =>
      Future.error(UnsupportedError('Merging a fork back is unavailable.'));
}

final class UnsupportedAgentChatLifecycleRepository
    extends AgentChatLifecycleRepository {
  const UnsupportedAgentChatLifecycleRepository();
}

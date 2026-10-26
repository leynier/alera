import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_feedback.g.dart';

/// The key of one chat on one paired host in [AgentChatFeedbackSubmissions].
String agentChatFeedbackKey(String hostId, String chatId) =>
    '$hostId\u0000$chatId';

/// The `/feedback` submissions of each chat, by host and chat, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the tab, which a host reconnect can rebuild
/// while the upload is still waiting on its answer.
@Riverpod(keepAlive: true)
class AgentChatFeedbackSubmissions extends _$AgentChatFeedbackSubmissions {
  final Set<String> _claimed = <String>{};

  @override
  Map<String, List<AgentChatFeedbackSubmission>> build() =>
      const <String, List<AgentChatFeedbackSubmission>>{};

  /// Claims a chat for one submission; `false` while one is in flight.
  bool claim(String hostId, String chatId) =>
      _claimed.add(agentChatFeedbackKey(hostId, chatId));

  void release(String hostId, String chatId) =>
      _claimed.remove(agentChatFeedbackKey(hostId, chatId));

  /// Uploads [command], typed as [text], which the person confirmed, then
  /// releases the claim.
  Future<AgentChatFeedbackSubmission> submit({
    required String hostId,
    required AgentChatRef chat,
    required AgentChatLifecycleRepository lifecycle,
    required AgentChatFeedbackCommand command,
    required String text,
  }) async {
    final key = agentChatFeedbackKey(hostId, chat.chatId);
    try {
      return await submitAgentChatFeedback(
        lifecycle: lifecycle,
        chat: chat,
        submission: AgentChatFeedbackSubmission(
          id: const Uuid().v4(),
          command: text,
          createdAt: DateTime.now().toUtc(),
        ),
        command: command,
        onUpdate: (submission) =>
            state = <String, List<AgentChatFeedbackSubmission>>{
              ...state,
              key: agentChatFeedbackUpsert(
                state[key] ?? const <AgentChatFeedbackSubmission>[],
                submission,
              ),
            },
      );
    } finally {
      release(hostId, chat.chatId);
    }
  }

  void dismiss(String hostId, String chatId, String id) {
    final key = agentChatFeedbackKey(hostId, chatId);
    final remaining = <AgentChatFeedbackSubmission>[
      for (final submission in state[key] ?? const [])
        if (submission.id != id) submission,
    ];
    state = <String, List<AgentChatFeedbackSubmission>>{
      for (final MapEntry(key: entry, :value) in state.entries)
        if (entry != key) entry: value,
      if (remaining.isNotEmpty) key: List.unmodifiable(remaining),
    };
  }
}

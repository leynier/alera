import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_feedback.g.dart';

/// The `/feedback` submissions of each chat, by chat id, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the chat tab so a hidden tab still finishes.
@Riverpod(keepAlive: true)
class AgentChatFeedbackSubmissions extends _$AgentChatFeedbackSubmissions {
  final Set<String> _claimed = <String>{};

  @override
  Map<String, List<AgentChatFeedbackSubmission>> build() =>
      const <String, List<AgentChatFeedbackSubmission>>{};

  /// Claims [chatId] for one submission; `false` while one is in flight.
  bool claim(String chatId) => _claimed.add(chatId);

  void release(String chatId) => _claimed.remove(chatId);

  /// Uploads [command], typed as [text], which the person confirmed, then
  /// releases the claim.
  Future<AgentChatFeedbackSubmission> submit(
    AgentChatRef chat,
    AgentChatFeedbackCommand command, {
    required String text,
  }) async {
    try {
      return await submitAgentChatFeedback(
        lifecycle: ref.read(agentChatLifecycleRepositoryProvider),
        chat: chat,
        submission: AgentChatFeedbackSubmission(
          id: ref.read(agentChatIdGeneratorProvider)(),
          command: text,
          createdAt: ref.read(agentChatClockProvider)().toUtc(),
        ),
        command: command,
        onUpdate: (submission) =>
            state = <String, List<AgentChatFeedbackSubmission>>{
              ...state,
              chat.chatId: agentChatFeedbackUpsert(
                state[chat.chatId] ?? const <AgentChatFeedbackSubmission>[],
                submission,
              ),
            },
      );
    } finally {
      release(chat.chatId);
    }
  }

  void dismiss(String chatId, String id) {
    final remaining = <AgentChatFeedbackSubmission>[
      for (final submission in state[chatId] ?? const [])
        if (submission.id != id) submission,
    ];
    state = <String, List<AgentChatFeedbackSubmission>>{
      for (final MapEntry(:key, :value) in state.entries)
        if (key != chatId) key: value,
      if (remaining.isNotEmpty) chatId: List.unmodifiable(remaining),
    };
  }
}

import 'package:alera_agent_chat/src/agent_chat_error_message.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_command.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';

/// What follows the slash in Codex's `/feedback`, which the composer runs
/// itself instead of sending it to the agent.
const String agentChatFeedbackCommandName = 'feedback';

/// T3 Code's guard for `/feedback` before the chat has a thread to upload.
const String agentChatFeedbackNeedsConversationMessage =
    'Send a message before you submit feedback.';

const String agentChatFeedbackConsentTitle = 'Send Feedback to OpenAI?';
const String agentChatFeedbackConsentConfirmLabel = 'Send Feedback';

/// Alera asks before uploading, unlike T3 Code: the upload leaves the
/// machine and cannot be taken back.
String agentChatFeedbackConsentMessage(AgentChatFeedbackCommand command) {
  const upload =
      'This uploads this conversation thread and the Codex logs to OpenAI. '
      'They can include your prompts, file contents, commands and their '
      'output from this session.';
  final reason = command.reason;
  return reason == null
      ? upload
      : '$upload\n\nYour description goes with them: "$reason"';
}

/// `/feedback` with what the person typed after it.
final class const AgentChatFeedbackCommand({final String? reason}) {
  @override
  bool operator ==(Object other) =>
      other is AgentChatFeedbackCommand && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

final RegExp _feedbackCommand = RegExp(
  r'^/feedback(?:\s+([\s\S]*))?$',
  caseSensitive: false,
);

/// T3 Code's `parseCodexFeedbackCommand`: the trimmed text is `/feedback`,
/// alone or followed by white space and a reason; anything else is `null`.
AgentChatFeedbackCommand? parseAgentChatFeedbackCommand(String text) {
  final match = _feedbackCommand.firstMatch(text.trim());
  if (match == null) return null;
  final reason = match.group(1)?.trim();
  return AgentChatFeedbackCommand(
    reason: reason == null || reason.isEmpty ? null : reason,
  );
}

/// Whether the composer runs `/feedback` for a chat: the runtime has the
/// verb and the agent lists the command. Otherwise the text stays a message.
bool agentChatFeedbackAvailable({
  required bool supported,
  required List<AgentChatProviderCommand> commands,
}) =>
    supported &&
    commands.any(
      (command) => command.name.toLowerCase() == agentChatFeedbackCommandName,
    );

/// The agent's commands as the `/` menu lists them. `/feedback` needs the
/// runtime verb, and T3 Code hides it until the chat has a conversation.
List<AgentChatProviderCommand> agentChatMenuProviderCommands(
  List<AgentChatProviderCommand> commands, {
  required bool feedbackSupported,
  required bool hasConversation,
}) {
  if (feedbackSupported && hasConversation) return commands;
  return <AgentChatProviderCommand>[
    for (final command in commands)
      if (command.name.toLowerCase() != agentChatFeedbackCommandName) command,
  ];
}

enum AgentChatFeedbackStatus { uploading, sent, failed }

/// One `/feedback` the person confirmed, as the chat shows it: uploading,
/// then sent with the id OpenAI files it under, or failed with the reason.
/// Kept on the device only, as T3 Code keeps it, because the upload does not
/// change the conversation.
final class const AgentChatFeedbackSubmission({
  /// Also the request id, so a retried request cannot upload twice.
  required final String id,
  required final String command,
  required final DateTime createdAt,
  final AgentChatFeedbackStatus status = .uploading,
  final String? feedbackId,
  final String? errorMessage,
}) {
  AgentChatFeedbackSubmission sent(String feedbackId) =>
      AgentChatFeedbackSubmission(
        id: id,
        command: command,
        createdAt: createdAt,
        status: .sent,
        feedbackId: feedbackId,
      );

  AgentChatFeedbackSubmission failed(String errorMessage) =>
      AgentChatFeedbackSubmission(
        id: id,
        command: command,
        createdAt: createdAt,
        status: .failed,
        errorMessage: errorMessage,
      );

  @override
  bool operator ==(Object other) =>
      other is AgentChatFeedbackSubmission &&
      other.id == id &&
      other.command == command &&
      other.createdAt == createdAt &&
      other.status == status &&
      other.feedbackId == feedbackId &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(id, command, createdAt, status, feedbackId, errorMessage);
}

/// T3 Code's `codexFeedbackNotice`: a title and the detail under it.
final class const AgentChatFeedbackNotice({
  required final String title,
  final String? detail,
});

AgentChatFeedbackNotice agentChatFeedbackNotice(
  AgentChatFeedbackSubmission submission,
) => switch (submission.status) {
  .uploading => const AgentChatFeedbackNotice(
    title: 'Sending feedback to OpenAI...',
  ),
  .sent => AgentChatFeedbackNotice(
    title: 'Feedback sent to OpenAI',
    detail: 'Thread ID: ${submission.feedbackId}',
  ),
  .failed => AgentChatFeedbackNotice(
    title: 'Could not send feedback to OpenAI',
    detail: submission.errorMessage,
  ),
};

/// [submissions] with [submission] replacing the entry of its id, or added
/// last when it is new.
List<AgentChatFeedbackSubmission> agentChatFeedbackUpsert(
  List<AgentChatFeedbackSubmission> submissions,
  AgentChatFeedbackSubmission submission,
) {
  final found = submissions.any((entry) => entry.id == submission.id);
  return List<AgentChatFeedbackSubmission>.unmodifiable(
    <AgentChatFeedbackSubmission>[
      for (final entry in submissions)
        entry.id == submission.id ? submission : entry,
      if (!found) submission,
    ],
  );
}

/// T3 Code's `submitCodexFeedback`: reports [submission] uploading, uploads
/// it, then reports how it ended. It never throws; a failure is the result.
Future<AgentChatFeedbackSubmission> submitAgentChatFeedback({
  required AgentChatLifecycleRepository lifecycle,
  required AgentChatRef chat,
  required AgentChatFeedbackSubmission submission,
  required AgentChatFeedbackCommand command,
  required void Function(AgentChatFeedbackSubmission submission) onUpdate,
}) async {
  onUpdate(submission);
  AgentChatFeedbackSubmission result;
  try {
    final feedbackId = await lifecycle.feedback(
      chat,
      requestId: submission.id,
      reason: command.reason,
    );
    result = submission.sent(feedbackId);
  } on Object catch (error) {
    result = submission.failed(agentChatErrorMessage(error));
  }
  onUpdate(result);
  return result;
}

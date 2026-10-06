import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class InboxUpdateRequired implements Exception {
  const InboxUpdateRequired();

  @override
  String toString() => 'Update the runtime to use the inbox.';
}

/// Sentence-case text for an inbox failure, keyed by the host's error code.
String inboxErrorMessage(Object error) {
  if (error is InboxUpdateRequired) return error.toString();
  if (error is TerminalHostConflictException) {
    return switch (error.code) {
      'inbox_pending_limit' => 'This agent already has 20 questions waiting. Wait for it to read them or cancel some.',
      'inbox_ambiguous_recipient' =>
        'More than one agent matches. Choose a specific terminal.',
      'inbox_no_recipient' => 'No running agent matches.',
      'inbox_unknown_recipient' =>
        'That terminal is no longer known to the runtime.',
      'inbox_thread_mismatch' =>
        'A follow-up must go to the same agent and inbox as the question.',
      'inbox_not_cancellable' =>
        'The agent already received this question, so it cannot be cancelled.',
      'inbox_question_not_found' ||
      'inbox_thread_not_found' => 'This question no longer exists.',
      'inbox_invalid_address' => 'Use an inbox address like ext:user, with lowercase letters, digits, dots, underscores or hyphens.',
      'inbox_invalid_expiry' => 'Choose an expiry between 1 minute and 7 days.',
      'message_too_large' => 'The question is too long.',
      _ => error.message,
    };
  }
  if (error is TerminalHostConnectionClosedException) {
    return 'The Alera runtime is not reachable.';
  }
  return error.toString();
}

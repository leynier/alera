import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';

/// Sentence-case text for an inbox failure, keyed by the runtime's error code.
/// Anything without a known code keeps the runtime's own text, without Dart
/// type prefixes.
String inboxErrorMessage(Object? error) {
  if (error is RuntimeRequestError) {
    return switch (error.code) {
      'inbox_pending_limit' => 'This agent already has 100 questions waiting. Wait for it to read them or cancel some.',
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
      _ => userFacingErrorMessage(error),
    };
  }
  return userFacingErrorMessage(error);
}

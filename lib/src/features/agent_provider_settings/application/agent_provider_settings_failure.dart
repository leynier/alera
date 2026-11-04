import 'package:alera_agent_chat/alera_agent_chat.dart';

/// Why a provider settings request did not apply, as the pane reports it.
enum AgentProviderFailureKind {
  /// Another device saved first; the latest values were reloaded.
  revisionConflict,

  /// The instance still has open chats and the removal was not confirmed.
  inUse,

  /// This client may not make that change.
  notAllowed,

  /// The host's runtime is too old for the request.
  updateRequired,

  /// The request never got an answer; it may still have applied.
  connection,

  /// The host rejected the request for another reason.
  rejected,
}

final class const AgentProviderSettingsFailure({
  required final AgentProviderFailureKind kind,
  required final String message,
}) implements Exception {
  factory from(Object error) {
    if (error is AgentProviderSettingsFailure) {
      return error;
    }
    if (error is AgentChatCapabilityRequired ||
        error is AgentChatUpdateRequired ||
        error is UnsupportedError) {
      return const AgentProviderSettingsFailure(
        kind: .updateRequired,
        message:
            'The Alera runtime on this host needs an update to manage '
            'providers.',
      );
    }
    if (error is AgentChatConnectionException) {
      return const AgentProviderSettingsFailure(
        kind: .connection,
        message:
            'Could not reach the Alera runtime on this host. Check the '
            'connection and try again.',
      );
    }
    if (error is AgentChatRequestException) {
      return switch (error.code) {
        'revisionConflict' => const AgentProviderSettingsFailure(
          kind: .revisionConflict,
          message:
              'Provider settings changed on another device. The latest '
              'values are loaded; review them and save again.',
        ),
        'providerInstanceInUse' => AgentProviderSettingsFailure(
          kind: .inUse,
          message: error.message,
        ),
        'notAllowed' => const AgentProviderSettingsFailure(
          kind: .notAllowed,
          message: 'This device is not allowed to make that change.',
        ),
        _ => AgentProviderSettingsFailure(
          kind: .rejected,
          message: error.message.trim().isEmpty
              ? 'The runtime rejected the change.'
              : error.message,
        ),
      };
    }
    return AgentProviderSettingsFailure(
      kind: .rejected,
      message: error.toString(),
    );
  }

  @override
  String toString() => message;
}

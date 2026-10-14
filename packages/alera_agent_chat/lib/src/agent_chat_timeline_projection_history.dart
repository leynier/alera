part of 'agent_chat_timeline_projection.dart';

/// The rewinds a settled turn can offer.
enum AgentChatRewindKind {
  /// Alera's transcript goes back; the next send starts a new agent session
  /// from the retained transcript. Files never change.
  transcript,

  /// The provider's own conversation rolls back to the turn as well. Files
  /// never change.
  conversation,

  /// Files go back to the checkpoint the provider took before the turn; the
  /// conversation stays.
  files,
}

/// Which rewinds a settled turn offers. Each needs the runtime verb (a host
/// capability the caller resolves) and, for native history, the live
/// adapter's proof in the session capabilities. Nothing is offered while the
/// session is busy or another native operation is unresolved, because the
/// runtime refuses those.
final class AgentChatRewindOptions {
  const AgentChatRewindOptions({
    this.transcript = false,
    this.conversation = false,
    this.files = false,
  });

  factory AgentChatRewindOptions.resolve({
    required AgentChatSession session,
    required bool transcriptSupported,
    required bool conversationSupported,
    required bool filesSupported,
    AgentChatNativeOperation? pendingOperation,
  }) {
    if (session.busy || pendingOperation != null) {
      return const AgentChatRewindOptions();
    }
    final native = session.capabilities.nativeHistory;
    return AgentChatRewindOptions(
      transcript: transcriptSupported,
      // Only an exact rollback to before a chosen turn can match the
      // transcript; removing a count of recent turns cannot.
      conversation: conversationSupported && native.rollbackBeforeTurn,
      files:
          filesSupported && native.rewindFiles && session.fileCheckpointing,
    );
  }

  final bool transcript;
  final bool conversation;
  final bool files;

  bool get any => transcript || conversation || files;

  /// The offered kinds, in the order both apps list them.
  List<AgentChatRewindKind> get kinds => <AgentChatRewindKind>[
    if (conversation) AgentChatRewindKind.conversation,
    if (transcript) AgentChatRewindKind.transcript,
    if (files) AgentChatRewindKind.files,
  ];
}

/// "Rewind Conversation", "Rewind Transcript", "Rewind Files".
String agentChatRewindLabel(AgentChatRewindKind kind) => switch (kind) {
  AgentChatRewindKind.transcript => 'Rewind Transcript',
  AgentChatRewindKind.conversation => 'Rewind Conversation',
  AgentChatRewindKind.files => 'Rewind Files',
};

/// One line under a rewind choice, saying what moves and what stays.
String agentChatRewindDescription(AgentChatRewindKind kind) => switch (kind) {
  AgentChatRewindKind.transcript =>
    'The chat goes back and the agent restarts from the transcript. Files '
        'stay as they are.',
  AgentChatRewindKind.conversation =>
    "The agent's own conversation goes back too. Files stay as they are.",
  AgentChatRewindKind.files =>
    "Files go back to this turn's checkpoint. The conversation stays.",
};

String agentChatRewindConfirmTitle(AgentChatRewindKind kind) =>
    '${agentChatRewindLabel(kind)}?';

String agentChatRewindConfirmMessage(AgentChatRewindKind kind) =>
    switch (kind) {
      AgentChatRewindKind.transcript =>
        "This turn and every later one leave the chat, and the turn's "
            'prompt returns to the composer. The next message starts a new '
            'agent session from the transcript. Files stay as they are.',
      AgentChatRewindKind.conversation =>
        "The agent's conversation goes back to before this turn, this turn "
            "and every later one leave the chat, and the turn's prompt "
            'returns to the composer. Files stay as they are.',
      AgentChatRewindKind.files =>
        'Files go back to the checkpoint the agent took before this turn. '
            'The conversation stays as it is. Only file changes the provider '
            'confirms are reported.',
    };

String agentChatRewindConfirmLabel(AgentChatRewindKind kind) =>
    kind == AgentChatRewindKind.files ? 'Rewind Files' : 'Rewind';

/// After a transcript or conversation rewind. It repeats only what the
/// runtime observed about files: unknown effects read as unverified, and an
/// acknowledgement alone proves nothing.
String agentChatRewindResultNotice(AgentChatRewindResult result) =>
    switch (result.filesystemChangesReverted) {
      true => 'Rewound the chat, and the provider reverted file changes.',
      false => 'Rewound the chat. Files stay as they are.',
      null => 'Rewound the chat. Whether any files changed is not verified. '
          'Check the workspace.',
    };

/// After a file rewind. An acknowledgement alone is not proof that files
/// changed, so only an observed effect reads as restored.
String agentChatFileRewindNotice(AgentChatFilesystemRewindResult result) =>
    switch (result.filesystemChangesReverted) {
      true => 'Files were restored to the checkpoint.',
      false => 'The provider did not restore any files.',
      null when result.filesystemRewindAcknowledged =>
        'The provider accepted the file rewind, but which files changed is '
            'not confirmed. Check the workspace.',
      null =>
        'The file rewind did not complete. Whether any files changed is not '
            'verified.',
    };

/// Send stays blocked while a native operation is unresolved; the draft is
/// kept.
const String agentChatNativeOperationSendBlockedHint =
    'Send is paused until the rewind is resolved.';

bool _isFileOperation(AgentChatNativeOperation operation) =>
    agentChatWireToken(operation.kind) == 'rewindfiles';

/// The heading of the notice for an unresolved native operation.
String agentChatNativeOperationTitle(AgentChatNativeOperation operation) {
  final files = _isFileOperation(operation);
  if (operation.recovery?.needsReconciliation ?? false) {
    return files ? 'File Rewind Needs a Decision' : 'Rewind Needs a Decision';
  }
  return files ? 'Rewinding Files' : 'Rewinding Conversation';
}

/// The runtime's own sentence when it gave one, otherwise a plain one.
String agentChatNativeOperationMessage(AgentChatNativeOperation operation) {
  final message = operation.recovery?.message.trim() ?? '';
  if (message.isNotEmpty) return message;
  return operation.recovery?.needsReconciliation ?? false
      ? 'Alera could not confirm how the rewind ended. Choose how to '
            'continue.'
      : agentChatNativeOperationSendBlockedHint;
}

/// Exactly the recovery actions the runtime allows for [operation], in a
/// fixed order. None run on their own: each is a person's choice.
List<AgentChatNativeHistoryAction> agentChatNativeOperationActions(
  AgentChatNativeOperation operation,
) {
  final recovery = operation.recovery;
  if (recovery == null) return const <AgentChatNativeHistoryAction>[];
  return <AgentChatNativeHistoryAction>[
    if (recovery.canFinishAcknowledged)
      AgentChatNativeHistoryAction.finishAcknowledged,
    if (recovery.canContinueFromCurrentFiles && _isFileOperation(operation))
      AgentChatNativeHistoryAction.continueFromCurrentFiles,
    if (recovery.canRestartFromTranscript)
      AgentChatNativeHistoryAction.restartFromTranscript,
    if (recovery.canCancelUnstarted)
      AgentChatNativeHistoryAction.cancelUnstarted,
  ];
}

String agentChatNativeOperationActionLabel(
  AgentChatNativeHistoryAction action,
) => switch (action) {
  AgentChatNativeHistoryAction.finishAcknowledged => 'Finish Rewind',
  AgentChatNativeHistoryAction.continueFromCurrentFiles =>
    'Keep Current Files',
  AgentChatNativeHistoryAction.restartFromTranscript =>
    'Restart From Transcript',
  AgentChatNativeHistoryAction.cancelUnstarted => 'Cancel Rewind',
};

/// What choosing [action] does, for the confirmation that precedes it.
String agentChatNativeOperationActionDescription(
  AgentChatNativeHistoryAction action,
) => switch (action) {
  AgentChatNativeHistoryAction.finishAcknowledged =>
    'The provider confirmed the rewind. Apply it to this chat.',
  AgentChatNativeHistoryAction.continueFromCurrentFiles =>
    'Keep working with the files as they are now. Nothing is restored.',
  AgentChatNativeHistoryAction.restartFromTranscript =>
    "Start a new agent session from the chat transcript. The provider's own "
        'history is not used. Files stay as they are.',
  AgentChatNativeHistoryAction.cancelUnstarted =>
    'The rewind never reached the provider. Drop it and keep the chat as it '
        'was.',
};

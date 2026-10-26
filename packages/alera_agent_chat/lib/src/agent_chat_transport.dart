/// Wire names shared by the runtime, the desktop app and the phone.
abstract final class AgentChatWire {
  static const String capability = 'agentChatV1';
  static const String deferredStartCapability = 'agentChatDeferredStartV1';
  static const String unselectedDraftCapability = 'agentChatUnselectedDraftV1';
  static const String preferencesCapability = 'agentChatPreferencesV1';
  static const String providerSettingsCapability =
      'agentChatProviderSettingsV1';
  static const String effortCapability = 'agentChatEffortV1';
  static const String queueSteerCapability = 'agentChatQueueSteerV1';
  static const String queueEditCapability = 'agentChatQueueEditV1';
  static const String queueReorderCapability = 'agentChatQueueReorderV1';
  static const String forkCapability = 'agentChatForkV1';
  static const String rewindCapability = 'agentChatRewindV1';
  static const String nativeRewindCapability = 'agentChatNativeRewindV1';
  static const String rewindFilesCapability = 'agentChatRewindFilesV1';
  static const String fileCheckpointsCapability = 'agentChatFileCheckpointsV1';
  static const String nativeHistoryCapability = 'agentChatNativeHistoryV1';

  /// `agentChat.send` takes `declineRequests`, declining those approvals and
  /// admitting the message in one runtime step.
  static const String approvalRedirectCapability =
      'agentChatApprovalRedirectV1';

  /// `agentChat.feedback`: Codex `/feedback` uploads the thread and logs.
  static const String feedbackCapability = 'agentChatFeedbackV1';
  static const String deleteCapability = 'agentChatDeleteV1';
  static const String approvalHistoryCapability = 'agentChatApprovalHistoryV1';
  static const String turnDiffCapability = 'agentChatTurnDiffV1';
  static const String skillsCapability = 'agentChatSkillsV1';
  static const String readCursorCapability = 'agentChatReadCursorV1';
  static const String attachmentUploadCapability =
      'agentChatAttachmentUploadV1';

  /// `agentChat.subagent` reads a provider-native sub-agent's own transcript
  /// and `agentChat.stopSubagent` stops it.
  static const String subagentThreadsCapability = 'agentChatSubagentThreadsV1';

  /// `agentChat.mergeBack` hands a fork's work to the chat it came from.
  static const String mergeBackCapability = 'agentChatMergeBackV1';

  /// Sessions carry the provider's `goal` and turns their `origin`.
  static const String goalCapability = 'agentChatGoalV1';

  /// ACP agents' native child sessions read as sub-agents, stop on their
  /// own, and turns may carry `origin: backgroundContinuation`.
  static const String acpChildSessionsCapability =
      'agentChatAcpChildSessionsV1';

  /// Sub-agents may carry a `workflow`; `agentChat.workflowScript` and
  /// `agentChat.workflowAgent` read its script and a member's answers.
  static const String workflowsCapability = 'agentChatWorkflowsV1';

  /// Snapshots and changes carry `contextTransfers`: the context moved into
  /// the chat by forks, merge-backs, handoffs and delegated work.
  static const String transfersCapability = 'agentChatTransfersV1';
  static const String tabKind = 'agentChat';

  /// Tab payload keys. [legacyChatIdKey] is read but never written.
  static const String chatIdKey = 'chatId';
  static const String legacyChatIdKey = 'agentChatId';
  static const String providerKey = 'provider';
  static const String providerInstanceIdKey = 'providerInstanceId';
  static const String modelKey = 'model';

  static const String changedEvent = 'agentChatChanged';
  static const String listChangedEvent = 'agentChatsChanged';
  static const String preferencesChangedEvent = 'agentChatPreferencesChanged';
  static const String providersChangedEvent = 'agentChatProvidersChanged';
  static const String deletedEvent = 'agentChatDeleted';

  static const String preferencesGet = 'agentChat.preferences.get';
  static const String preferencesUpdate = 'agentChat.preferences.update';
  static const String providerInstancesGet = 'agentChat.providerInstances.get';
  static const String providerInstancesUpsert =
      'agentChat.providerInstances.upsert';
  static const String providerInstancesRemove =
      'agentChat.providerInstances.remove';
  static const String providerInstancesRemovalImpact =
      'agentChat.providerInstances.removalImpact';
  static const String secretsSet = 'agentChat.secrets.set';
  static const String secretsClear = 'agentChat.secrets.clear';

  static const String providers = 'agentChat.providers';
  static const String create = 'agentChat.create';
  static const String reopen = 'agentChat.reopen';
  static const String snapshot = 'agentChat.snapshot';
  static const String history = 'agentChat.history';
  static const String payload = 'agentChat.payload';
  static const String send = 'agentChat.send';
  static const String attachmentStart = 'agentChat.attachment.start';
  static const String attachmentChunk = 'agentChat.attachment.chunk';
  static const String attachmentComplete = 'agentChat.attachment.complete';
  static const String attachmentCancel = 'agentChat.attachment.cancel';
  static const String queueCancel = 'agentChat.queueCancel';
  static const String queueEdit = 'agentChat.queueEdit';
  static const String queueReorder = 'agentChat.queueReorder';
  static const String queueSteer = 'agentChat.queueSteer';
  static const String markRead = 'agentChat.markRead';
  static const String fork = 'agentChat.fork';
  static const String rewind = 'agentChat.rewind';
  static const String rewindFiles = 'agentChat.rewindFiles';
  static const String fileCheckpointsConfigure =
      'agentChat.fileCheckpoints.configure';
  static const String nativeHistoryReconcile =
      'agentChat.nativeHistory.reconcile';
  static const String nativeHistoryOperation =
      'agentChat.nativeHistory.operation';
  static const String delete = 'agentChat.delete';
  static const String approvalHistory = 'agentChat.approvalHistory';
  static const String turnDiff = 'agentChat.turnDiff';
  static const String skills = 'agentChat.skills';
  static const String interrupt = 'agentChat.interrupt';
  static const String respond = 'agentChat.respond';
  static const String feedback = 'agentChat.feedback';
  static const String configure = 'agentChat.configure';
  static const String rename = 'agentChat.rename';
  static const String subagent = 'agentChat.subagent';
  static const String workflowScript = 'agentChat.workflowScript';
  static const String workflowAgent = 'agentChat.workflowAgent';
  static const String stopSubagent = 'agentChat.stopSubagent';
  static const String mergeBack = 'agentChat.mergeBack';
  static const String recover = 'agentChat.recover';
  static const String close = 'agentChat.close';
  static const String list = 'agentChat.list';
}

/// Events every transport adapter emits for its own connection lifecycle,
/// whatever its native names are.
abstract final class AgentChatTransportEvents {
  static const String connected = 'agentChat.transport.connected';
  static const String disconnected = 'agentChat.transport.disconnected';
}

final class const AgentChatTransportEvent(
  final String name,
  final Map<String, Object?> payload,
);

/// The runtime connection as the shared repository needs it. Each app adapts
/// its own runtime client: desktop over the local socket, the phone over its
/// paired gateway. Failures must surface as [AgentChatRequestException] or
/// [AgentChatConnectionException].
abstract interface class AgentChatTransport {
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  });

  Stream<AgentChatTransportEvent> get events;

  Future<bool> supportsCapability(String capability);
}

/// The runtime rejected a request; [code] is its `errorCode` when it sent one.
final class const AgentChatRequestException({
  required final String message,
  final String? code,
  final Map<String, Object?> details = const <String, Object?>{},
}) implements Exception {
  @override
  String toString() => message;
}

/// The request never got an answer: the connection closed or timed out. A
/// mutation may still have been applied; retry with the same request id.
final class const AgentChatConnectionException(final String message)
    implements Exception {
  @override
  String toString() => message;
}

/// The runtime does not advertise [AgentChatWire.capability].
final class const AgentChatUpdateRequired() implements Exception {
  @override
  String toString() =>
      'This Alera runtime does not support agent chats yet. Update it to '
      'continue.';
}

final class const AgentChatCapabilityRequired(final String capability)
    implements Exception {
  @override
  String toString() =>
      'This Alera runtime needs an update to support $capability.';
}

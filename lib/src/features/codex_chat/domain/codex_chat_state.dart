part of 'codex_chat_models.dart';

@immutable
class const CodexThreadRecovery({
  required final String kind,
  required final String message,
}) {
  factory fromJson(Object? value) {
    final json = value is Map ? Map<String, Object?>.from(value) : null;
    if (json == null || json['kind'] is! String) {
      return const CodexThreadRecovery(
        kind: 'missingRollout',
        message: 'The saved Codex context is no longer available.',
      );
    }
    return CodexThreadRecovery(
      kind: json['kind']! as String,
      message:
          json['message']?.toString() ??
          'The saved Codex context is no longer available.',
    );
  }
}

@immutable
class const CodexChatState({
  final bool loading = true,
  final bool sending = false,
  final bool interrupting = false,
  final bool supportsSessions = false,
  final bool supportsAutoReview = false,
  final bool supportsGoals = false,
  final CodexChatSnapshot snapshot = const CodexChatSnapshot(),
  final String? activeCwd,
  final String? historyNextCursor,
  final List<CodexModelOption> models = const <CodexModelOption>[],
  final List<Map<String, Object?>> collaborationModes =
      const <Map<String, Object?>>[],
  final List<Map<String, Object?>> skills = const <Map<String, Object?>>[],
  final List<Map<String, Object?>> apps = const <Map<String, Object?>>[],
  final String? selectedModel,
  final String reasoningEffort = 'medium',
  final String speedMode = 'normal',
  final String permissionMode = 'on-request',
  final bool planMode = false,
  final String? collaborationMode,
  final Set<String> chatFeatures = const <String>{},
  final Map<String, Object?> queueState = const <String, Object?>{},
  final int historyRevision = 0,
  final List<CodexQueuedMessage> queuedMessages = const <CodexQueuedMessage>[],
  final CodexThreadRecovery? recovery,
  final String? error,
}) {
  bool get supportsSharedQueue => chatFeatures.contains('codexSharedQueueV1');
  bool get sharedQueueUnavailable =>
      !supportsSharedQueue && queueState.containsKey('revision');
  bool get supportsFork => chatFeatures.contains('codexForkV1');
  bool get supportsHistoryEdit =>
      chatFeatures.contains('codexHistoryEditV1') &&
      queueState['historyEditUnavailableReason'] == null;
  bool get queuePaused => queueState['paused'] == true;
  bool get historyOutdated =>
      (queueState['historyRevision'] as int? ?? 0) > historyRevision;
  bool get historyLocked =>
      historyOutdated || queueState['historyLocked'] == true;

  bool get busy => sending || snapshot.isBusy;

  CodexModelOption? get selectedModelOption {
    for (final model in models) {
      if (model.id == selectedModel) return model;
    }
    return null;
  }

  CodexChatState copyWith({
    bool? loading,
    Set<String>? chatFeatures,
    Map<String, Object?>? queueState,
    int? historyRevision,
    bool? sending,
    bool? interrupting,
    bool? supportsSessions,
    bool? supportsAutoReview,
    bool? supportsGoals,
    CodexChatSnapshot? snapshot,
    Object? activeCwd = _keepActiveCwd,
    Object? historyNextCursor = _keepHistoryNextCursor,
    List<CodexModelOption>? models,
    List<Map<String, Object?>>? collaborationModes,
    List<Map<String, Object?>>? skills,
    List<Map<String, Object?>>? apps,
    Object? selectedModel = _keepSelectedModel,
    String? reasoningEffort,
    String? speedMode,
    String? permissionMode,
    bool? planMode,
    Object? collaborationMode = _keepCollaborationMode,
    List<CodexQueuedMessage>? queuedMessages,
    Object? recovery = _keepRecovery,
    Object? error = _keepError,
  }) => CodexChatState(
    loading: loading ?? this.loading,
    chatFeatures: chatFeatures ?? this.chatFeatures,
    queueState: queueState ?? this.queueState,
    historyRevision: historyRevision ?? this.historyRevision,
    sending: sending ?? this.sending,
    interrupting: interrupting ?? this.interrupting,
    supportsSessions: supportsSessions ?? this.supportsSessions,
    supportsAutoReview: supportsAutoReview ?? this.supportsAutoReview,
    supportsGoals: supportsGoals ?? this.supportsGoals,
    snapshot: snapshot ?? this.snapshot,
    activeCwd: identical(activeCwd, _keepActiveCwd)
        ? this.activeCwd
        : activeCwd as String?,
    historyNextCursor: identical(historyNextCursor, _keepHistoryNextCursor)
        ? this.historyNextCursor
        : historyNextCursor as String?,
    models: models ?? this.models,
    collaborationModes: collaborationModes ?? this.collaborationModes,
    skills: skills ?? this.skills,
    apps: apps ?? this.apps,
    selectedModel: identical(selectedModel, _keepSelectedModel)
        ? this.selectedModel
        : selectedModel as String?,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    speedMode: speedMode ?? this.speedMode,
    permissionMode: permissionMode ?? this.permissionMode,
    planMode: planMode ?? this.planMode,
    collaborationMode: identical(collaborationMode, _keepCollaborationMode)
        ? this.collaborationMode
        : collaborationMode as String?,
    queuedMessages: queuedMessages ?? this.queuedMessages,
    recovery: identical(recovery, _keepRecovery)
        ? this.recovery
        : recovery as CodexThreadRecovery?,
    error: identical(error, _keepError) ? this.error : error as String?,
  );
}

const Object _keepError = Object();
const Object _keepSelectedModel = Object();
const Object _keepRecovery = Object();
const Object _keepCollaborationMode = Object();
const Object _keepActiveCwd = Object();
const Object _keepHistoryNextCursor = Object();

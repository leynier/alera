part of 'codex_chat_models.dart';

@immutable
class CodexThreadRecovery {
  const CodexThreadRecovery({required this.kind, required this.message});

  factory CodexThreadRecovery.fromJson(Object? value) {
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

  final String kind;
  final String message;
}

@immutable
class CodexChatState {
  const CodexChatState({
    this.loading = true,
    this.sending = false,
    this.interrupting = false,
    this.supportsSessions = false,
    this.supportsAutoReview = false,
    this.supportsGoals = false,
    this.snapshot = const CodexChatSnapshot(),
    this.activeCwd,
    this.historyNextCursor,
    this.models = const <CodexModelOption>[],
    this.collaborationModes = const <Map<String, Object?>>[],
    this.skills = const <Map<String, Object?>>[],
    this.apps = const <Map<String, Object?>>[],
    this.selectedModel,
    this.reasoningEffort = 'medium',
    this.speedMode = 'normal',
    this.permissionMode = 'on-request',
    this.planMode = false,
    this.collaborationMode,
    this.queuedMessages = const <CodexQueuedMessage>[],
    this.recovery,
    this.error,
  });

  final bool loading;
  final bool sending;
  final bool interrupting;
  final bool supportsSessions;
  final bool supportsAutoReview;
  final bool supportsGoals;
  final CodexChatSnapshot snapshot;
  final String? activeCwd;
  final String? historyNextCursor;
  final List<CodexModelOption> models;
  final List<Map<String, Object?>> collaborationModes;
  final List<Map<String, Object?>> skills;
  final List<Map<String, Object?>> apps;
  final String? selectedModel;
  final String reasoningEffort;
  final String speedMode;
  final String permissionMode;
  final bool planMode;
  final String? collaborationMode;
  final List<CodexQueuedMessage> queuedMessages;
  final CodexThreadRecovery? recovery;
  final String? error;

  bool get busy => sending || snapshot.isBusy;

  CodexModelOption? get selectedModelOption {
    for (final model in models) {
      if (model.id == selectedModel) return model;
    }
    return null;
  }

  CodexChatState copyWith({
    bool? loading,
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

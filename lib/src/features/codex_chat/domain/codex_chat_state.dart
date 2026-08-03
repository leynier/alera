part of 'codex_chat_models.dart';

@immutable
class CodexChatState {
  const CodexChatState({
    this.loading = true,
    this.sending = false,
    this.interrupting = false,
    this.snapshot = const CodexChatSnapshot(),
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
    this.error,
  });

  final bool loading;
  final bool sending;
  final bool interrupting;
  final CodexChatSnapshot snapshot;
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
    CodexChatSnapshot? snapshot,
    List<CodexModelOption>? models,
    List<Map<String, Object?>>? collaborationModes,
    List<Map<String, Object?>>? skills,
    List<Map<String, Object?>>? apps,
    String? selectedModel,
    String? reasoningEffort,
    String? speedMode,
    String? permissionMode,
    bool? planMode,
    Object? collaborationMode = _keepCollaborationMode,
    List<CodexQueuedMessage>? queuedMessages,
    Object? error = _keepError,
  }) => CodexChatState(
    loading: loading ?? this.loading,
    sending: sending ?? this.sending,
    interrupting: interrupting ?? this.interrupting,
    snapshot: snapshot ?? this.snapshot,
    models: models ?? this.models,
    collaborationModes: collaborationModes ?? this.collaborationModes,
    skills: skills ?? this.skills,
    apps: apps ?? this.apps,
    selectedModel: selectedModel ?? this.selectedModel,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    speedMode: speedMode ?? this.speedMode,
    permissionMode: permissionMode ?? this.permissionMode,
    planMode: planMode ?? this.planMode,
    collaborationMode: identical(collaborationMode, _keepCollaborationMode)
        ? this.collaborationMode
        : collaborationMode as String?,
    queuedMessages: queuedMessages ?? this.queuedMessages,
    error: identical(error, _keepError) ? this.error : error as String?,
  );
}

const Object _keepError = Object();
const Object _keepCollaborationMode = Object();

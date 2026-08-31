part of 'mobile_codex_chat_screen.dart';

class _MobileFooterState {
  _MobileFooterState(this.state, {required this.supportsGoals})
    : _progressSignature = _mobileProgressSignature(
        state.timelineCells,
        state.activeTurnId,
      );

  final MobileCodexState state;
  final bool supportsGoals;
  final String _progressSignature;

  @override
  bool operator ==(Object other) =>
      other is _MobileFooterState &&
      identical(state.models, other.state.models) &&
      identical(state.skills, other.state.skills) &&
      identical(state.apps, other.state.apps) &&
      identical(state.collaborationModes, other.state.collaborationModes) &&
      identical(state.pendingRequests, other.state.pendingRequests) &&
      identical(state.queuedMessages, other.state.queuedMessages) &&
      identical(state.queueState, other.state.queueState) &&
      identical(state.chatFeatures, other.state.chatFeatures) &&
      state.historyRevision == other.state.historyRevision &&
      state.hasCompletedTurns == other.state.hasCompletedTurns &&
      identical(state.promptHistory, other.state.promptHistory) &&
      state.title == other.state.title &&
      state.selectedModel == other.state.selectedModel &&
      state.reasoningEffort == other.state.reasoningEffort &&
      state.speedMode == other.state.speedMode &&
      state.permissionMode == other.state.permissionMode &&
      state.planMode == other.state.planMode &&
      state.collaborationMode == other.state.collaborationMode &&
      state.recovery?.kind == other.state.recovery?.kind &&
      state.recovery?.message == other.state.recovery?.message &&
      state.contextUsed == other.state.contextUsed &&
      state.contextLimit == other.state.contextLimit &&
      state.activeTurnId == other.state.activeTurnId &&
      state.sending == other.state.sending &&
      state.interrupting == other.state.interrupting &&
      state.mcpInitializing == other.state.mcpInitializing &&
      state.error == other.state.error &&
      state.goal == other.state.goal &&
      supportsGoals == other.supportsGoals &&
      state.shouldShowImplementPlan == other.state.shouldShowImplementPlan &&
      _progressSignature == other._progressSignature;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    identityHashCode(state.models),
    identityHashCode(state.skills),
    identityHashCode(state.apps),
    identityHashCode(state.collaborationModes),
    identityHashCode(state.pendingRequests),
    identityHashCode(state.queuedMessages),
    identityHashCode(state.promptHistory),
    state.hasCompletedTurns,
    state.title,
    state.selectedModel,
    state.reasoningEffort,
    state.speedMode,
    state.permissionMode,
    state.planMode,
    state.collaborationMode,
    state.recovery?.kind,
    state.recovery?.message,
    state.contextUsed,
    state.contextLimit,
    state.activeTurnId,
    state.sending,
    state.interrupting,
    state.mcpInitializing,
    state.error,
    state.goal,
    supportsGoals,
    state.shouldShowImplementPlan,
    _progressSignature,
  ]);
}

String _mobileProgressSignature(
  List<MobileCodexTimelineCell> cells,
  String? activeTurnId,
) {
  if (activeTurnId == null) return '';
  for (final cell in cells.reversed) {
    if (cell.turnId != activeTurnId) continue;
    final plan = cell.metadata['plan'];
    if (plan is List && plan.isNotEmpty) return jsonEncode(plan);
  }
  return '';
}

import 'package:alera_automations/alera_automations.dart';

class const AutomationComposerState({
  final AutomationDraft draft = const AutomationDraft(),
  final AutomationDraft initialDraft = const AutomationDraft(),
  final AutomationRecord? editing,
  final AutomationReadiness? readiness,
  final AutomationReadiness? preview,
  final bool checking = false,
  final bool submitting = false,
  final bool showErrors = false,
  final String? error,
  final String requestKey = '',
  final String? requestPayload,
  final bool initialized = false,
}) {
  AutomationComposerState copyWith({
    AutomationDraft? draft,
    AutomationDraft? initialDraft,
    AutomationRecord? editing,
    AutomationReadiness? Function()? readiness,
    AutomationReadiness? Function()? preview,
    bool? checking,
    bool? submitting,
    bool? showErrors,
    String? Function()? error,
    String? requestKey,
    String? requestPayload,
  }) => AutomationComposerState(
    draft: draft ?? this.draft,
    initialDraft: initialDraft ?? this.initialDraft,
    editing: editing ?? this.editing,
    readiness: readiness == null ? this.readiness : readiness(),
    preview: preview == null ? this.preview : preview(),
    checking: checking ?? this.checking,
    submitting: submitting ?? this.submitting,
    showErrors: showErrors ?? this.showErrors,
    error: error == null ? this.error : error(),
    requestKey: requestKey ?? this.requestKey,
    requestPayload: requestPayload ?? this.requestPayload,
    initialized: initialized,
  );

  /// Whether saving would change anything, so closing has to ask first.
  bool get isDirty => draft.definitionKey != initialDraft.definitionKey;

  bool get editsDraft => editing?.state == 'draft';

  /// Readiness errors block activating, not saving a draft.
  bool get readinessBlocks => readiness?.errors.isNotEmpty ?? false;

  /// The controls to outline in red: local problems once the user tried to
  /// save, and every runtime error as soon as it is known.
  Set<AutomationComposerProperty> get flaggedProperties =>
      <AutomationComposerProperty>{
        if (showErrors) ...draft.localProblems.keys,
        for (final issue in readiness?.errors ?? <AutomationReadinessIssue>[])
          ?automationIssueProperty(issue, targetType: draft.targetType),
      };
}

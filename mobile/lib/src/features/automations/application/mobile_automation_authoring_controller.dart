import 'dart:convert';

import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mobile_automation_authoring_controller.g.dart';

enum AutomationAuthoringStep(final String label) {
  what('What'),
  when('When'),
  where('Where'),
  review('Review'),
}

class const AutomationAuthoringState({
  final AutomationDraft draft = const AutomationDraft(),
  final AutomationAuthoringStep step = AutomationAuthoringStep.what,
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
  AutomationAuthoringState copyWith({
    AutomationDraft? draft,
    AutomationAuthoringStep? step,
    AutomationReadiness? Function()? readiness,
    AutomationReadiness? Function()? preview,
    bool? checking,
    bool? submitting,
    bool? showErrors,
    String? Function()? error,
    String? requestKey,
    String? requestPayload,
  }) => AutomationAuthoringState(
    draft: draft ?? this.draft,
    step: step ?? this.step,
    editing: editing,
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

  String? stepError(AutomationAuthoringStep step) => switch (step) {
    AutomationAuthoringStep.what => draft.whatError,
    AutomationAuthoringStep.when => draft.whenError,
    AutomationAuthoringStep.where => draft.whereError,
    AutomationAuthoringStep.review =>
      draft.numberErrors.isNotEmpty
          ? 'Fix the highlighted advanced settings.'
          : readiness?.errors.isNotEmpty == true
          ? 'Fix the problems below before saving.'
          : null,
  };
}

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.
@riverpod
class MobileAutomationAuthoringController
    extends _$MobileAutomationAuthoringController {
  @override
  AutomationAuthoringState build(String hostId, int session) =>
      AutomationAuthoringState(requestKey: const Uuid().v4());

  void initialize(AutomationDraft draft, {AutomationRecord? editing}) {
    state = AutomationAuthoringState(
      draft: draft,
      editing: editing,
      requestKey: state.requestKey,
      initialized: true,
    );
  }

  void update(AutomationDraft Function(AutomationDraft draft) change) {
    state = state.copyWith(
      draft: change(state.draft),
      readiness: () => null,
      error: () => null,
    );
  }

  bool next() {
    final error = state.stepError(state.step);
    if (error != null) {
      state = state.copyWith(showErrors: true);
      return false;
    }
    final index = state.step.index;
    if (index < AutomationAuthoringStep.values.length - 1) {
      state = state.copyWith(
        step: AutomationAuthoringStep.values[index + 1],
        showErrors: false,
      );
    }
    return true;
  }

  void back() {
    final index = state.step.index;
    if (index > 0) {
      state = state.copyWith(
        step: AutomationAuthoringStep.values[index - 1],
        showErrors: false,
      );
    }
  }

  void goTo(AutomationAuthoringStep step) {
    for (final earlier in AutomationAuthoringStep.values.take(step.index)) {
      if (state.stepError(earlier) != null) {
        state = state.copyWith(step: earlier, showErrors: true);
        return;
      }
    }
    state = state.copyWith(step: step, showErrors: false);
  }

  Future<void> refreshPreview() async {
    final schedule = state.draft;
    if (schedule.whenError != null) return;
    try {
      final repository = await ref.read(
        mobileAutomationRepositoryProvider(hostId).future,
      );
      final preview = await repository.previewSchedule(
        schedule.schedule.toSchedule(timezone: schedule.timezone),
      );
      if (preview == null ||
          !ref.mounted ||
          !identical(state.draft, schedule)) {
        return;
      }
      state = state.copyWith(
        preview: () => preview,
        draft: schedule.timezone == null && preview.timezone != null
            ? schedule.copyWith(timezone: preview.timezone)
            : null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        preview: () => AutomationReadiness(
          ready: false,
          issues: <AutomationReadinessIssue>[
            AutomationReadinessIssue(
              code: 'schedule',
              message: '$error',
              severity: AutomationIssueSeverity.error,
              field: 'schedule',
            ),
          ],
        ),
      );
    }
  }

  Future<void> checkReadiness() async {
    final draft = state.draft;
    state = state.copyWith(checking: true);
    try {
      final repository = await ref.read(
        mobileAutomationRepositoryProvider(hostId).future,
      );
      final readiness = await repository.readiness(<String, Object?>{
        ...draft.toDefinition(),
        if (state.editing case final editing?) 'id': editing.id,
      });
      if (!ref.mounted) return;
      state = state.copyWith(readiness: () => readiness, checking: false);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(checking: false, error: () => '$error');
    }
  }

  /// The create request key makes a retry of an ambiguous response
  /// idempotent. It is kept while the payload is the same and replaced once
  /// the draft changes, so a corrected draft is saved instead of being matched
  /// to the earlier attempt.
  String _requestKeyFor(JsonMap definition) {
    final payload = jsonEncode(definition);
    final previous = state.requestPayload;
    final key = previous == null || previous == payload
        ? state.requestKey
        : const Uuid().v4();
    state = state.copyWith(requestKey: key, requestPayload: payload);
    return key;
  }

  /// Creates (Active unless [asDraft]) or saves an edit. Editing an Active
  /// definition keeps it Active.
  Future<AutomationRecord?> submit({bool asDraft = false}) async {
    for (final step in AutomationAuthoringStep.values.take(3)) {
      if (state.stepError(step) != null) {
        state = state.copyWith(step: step, showErrors: true);
        return null;
      }
    }
    if (state.draft.numberErrors.isNotEmpty) {
      state = state.copyWith(
        step: AutomationAuthoringStep.review,
        showErrors: true,
      );
      return null;
    }
    state = state.copyWith(submitting: true, error: () => null);
    try {
      final repository = await ref.read(
        mobileAutomationRepositoryProvider(hostId).future,
      );
      final editing = state.editing;
      final definition = state.draft.toDefinition(draft: asDraft);
      final saved = editing == null
          ? await repository.create(
              definition,
              requestKey: _requestKeyFor(definition),
            )
          : await repository.patch(editing, definition);
      if (ref.mounted) state = state.copyWith(submitting: false);
      return saved;
    } on AutomationReadinessException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          readiness: () => error.readiness,
          step: AutomationAuthoringStep.review,
        );
      }
      return null;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(submitting: false, error: () => '$error');
      }
      return null;
    }
  }
}

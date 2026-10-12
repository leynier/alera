import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/automations/application/automation_composer_defaults.dart';
import 'package:alera/src/features/automations/application/automation_composer_state.dart';
import 'package:alera/src/features/automations/application/automation_project_branches.dart';
import 'package:alera/src/features/automations/application/automation_project_checkouts.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

export 'package:alera/src/features/automations/application/automation_composer_state.dart';

part 'automation_composer_controller.g.dart';
part 'automation_composer_seeding.dart';

/// Quiet period after the last edit before the runtime checks the draft.
const Duration automationReadinessDebounce = Duration(milliseconds: 600);

/// One composer dialog. Every edit is checked locally at once; once the draft
/// is complete the runtime checks it too (`automation.readiness`), shortly
/// after the user stops editing, so its target, profile and host problems
/// show before saving. Nothing here asks for approval.
@riverpod
class AutomationComposerController extends _$AutomationComposerController
    with _AutomationComposerSeeding {
  Timer? _previewTimer;
  Timer? _readinessTimer;

  @override
  AutomationComposerState build(int session) {
    ref.onDispose(() {
      _previewTimer?.cancel();
      _readinessTimer?.cancel();
    });
    return AutomationComposerState(requestKey: const Uuid().v4());
  }

  /// [seedProjectId] is the project the composer was opened from, whose only
  /// folder becomes the destination when nothing else could be seeded.
  void initialize(
    AutomationDraft draft, {
    AutomationRecord? editing,
    String? seedProjectId,
  }) {
    state = AutomationComposerState(
      draft: draft,
      initialDraft: draft,
      editing: editing,
      requestKey: state.requestKey,
      initialized: true,
    );
    unawaited(refreshPreview());
    _scheduleReadiness(immediately: editing != null);
    _requestBranch(draft, seed: true);
    if (seedProjectId != null && draft.targetType == null) {
      unawaited(_seedProjectFolder(seedProjectId));
    }
  }

  @override
  void update(AutomationDraft Function(AutomationDraft draft) change) {
    final previous = state.draft;
    final next = _normalized(change(previous));
    state = state.copyWith(draft: next, error: () => null);
    if (next.schedule != previous.schedule ||
        next.timezone != previous.timezone) {
      _previewTimer?.cancel();
      _previewTimer = Timer(
        AleraTokens.durationSlow,
        () => unawaited(refreshPreview()),
      );
    }
    _scheduleReadiness();
    _requestBranch(next, seed: false);
  }

  /// A reused workspace has to outlive the run, so reuse never keeps the
  /// cleanup the runtime would reject it with.
  AutomationDraft _normalized(AutomationDraft draft) =>
      draft.reusePolicy.reuses && draft.cleanupPolicy != 'preserve'
      ? draft.copyWith(cleanupPolicy: 'preserve')
      : draft;

  @override
  void _scheduleReadiness({bool immediately = false}) {
    _readinessTimer?.cancel();
    if (state.draft.localProblems.isNotEmpty) {
      if (state.readiness != null || state.checking) {
        state = state.copyWith(readiness: () => null, checking: false);
      }
      return;
    }
    if (immediately) {
      unawaited(checkReadiness());
      return;
    }
    _readinessTimer = Timer(
      automationReadinessDebounce,
      () => unawaited(checkReadiness()),
    );
  }

  Future<void> refreshPreview() async {
    final draft = state.draft;
    if (draft.whenError != null) return;
    final capabilities = await ref.read(
      automationRuntimeCapabilitiesProvider.future,
    );
    if (!capabilities.authoring || !ref.mounted) return;
    try {
      final preview = await ref
          .read(automationRepositoryProvider)
          .previewSchedule(draft.schedule.toSchedule(timezone: draft.timezone));
      if (!ref.mounted || !identical(state.draft, draft)) return;
      final zone = preview.timezone;
      state = state.copyWith(preview: () => preview);
      // The runtime's own zone fills an unset one without counting as an
      // edit.
      if (draft.timezone == null && zone != null) {
        _seed(
          (current) => current.timezone == null
              ? current.copyWith(timezone: zone)
              : current,
        );
      }
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        preview: () => AutomationReadiness(
          ready: false,
          issues: <AutomationReadinessIssue>[
            AutomationReadinessIssue(
              code: 'schedule',
              message: automationErrorMessage(error),
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
    if (draft.localProblems.isNotEmpty) return;
    final capabilities = await ref.read(
      automationRuntimeCapabilitiesProvider.future,
    );
    if (!capabilities.authoring || !ref.mounted) return;
    state = state.copyWith(checking: true);
    try {
      final readiness = await ref
          .read(automationRepositoryProvider)
          .readiness(
            draft: <String, Object?>{
              ...draft.toDefinition(supportsReuse: capabilities.reuse),
              if (state.editing case final editing?) 'id': editing.id,
            },
          );
      if (!ref.mounted || !identical(state.draft, draft)) return;
      state = state.copyWith(readiness: () => readiness, checking: false);
    } catch (error) {
      if (!ref.mounted || !identical(state.draft, draft)) return;
      state = state.copyWith(
        checking: false,
        error: () => automationErrorMessage(error),
      );
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

  /// Creates the automation, Active unless [asDraft], or saves an edit, which
  /// keeps the stored state. [activate] then turns a saved draft on.
  Future<AutomationRecord?> submit({
    bool asDraft = false,
    bool activate = false,
  }) async {
    if (state.draft.localProblems.isNotEmpty) {
      state = state.copyWith(showErrors: true);
      return null;
    }
    final repository = ref.read(automationRepositoryProvider);
    final capabilities = await ref.read(
      automationRuntimeCapabilitiesProvider.future,
    );
    if (!ref.mounted) return null;
    state = state.copyWith(submitting: true, error: () => null);
    final draft = state.draft;
    try {
      final editing = state.editing;
      final definition = draft.toDefinition(
        draft: asDraft,
        supportsReuse: capabilities.reuse,
      );
      var saved = editing == null
          ? await repository.create(
              definition,
              authoring: capabilities.authoring,
              requestKey: _requestKeyFor(definition),
            )
          : await repository.patch(
              editing,
              definition,
              authoring: capabilities.authoring,
            );
      if (ref.mounted) state = state.copyWith(editing: saved);
      if (activate && saved.state == 'draft') {
        saved = await repository.activate(saved);
      }
      ref
          .read(automationLastAgentProfileProvider.notifier)
          .remember(draft.field(.agentProfileId));
      if (ref.mounted) {
        state = state.copyWith(submitting: false, initialDraft: draft);
      }
      return saved;
    } on AutomationReadinessException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          readiness: () => error.readiness,
        );
      }
      return null;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          error: () => automationErrorMessage(error),
        );
      }
      return null;
    }
  }

  /// Clears the bound target of the automation being edited.
  Future<void> unbind() async {
    final editing = state.editing;
    if (editing == null) return;
    try {
      final record = await ref
          .read(automationRepositoryProvider)
          .unbind(editing.id);
      if (ref.mounted) state = state.copyWith(editing: record);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(error: () => automationErrorMessage(error));
      }
    }
  }
}

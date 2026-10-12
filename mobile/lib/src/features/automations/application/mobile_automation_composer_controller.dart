import 'dart:async';
import 'dart:convert';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_defaults.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_state.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_destinations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

export 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_state.dart';

part 'mobile_automation_composer_controller.g.dart';

/// Quiet period after the last edit before the runtime checks the draft.
const Duration mobileAutomationReadinessDebounce = Duration(milliseconds: 600);

/// One composer screen, for creating and editing. Every edit is checked
/// locally at once; a complete draft is also checked by the runtime
/// (`automation.readiness`) shortly after the user stops editing.
@riverpod
class MobileAutomationComposerController
    extends _$MobileAutomationComposerController {
  Timer? _previewTimer;
  Timer? _readinessTimer;
  String? _branchRequestedFor;

  @override
  MobileAutomationComposerState build(String hostId, int session) {
    ref.onDispose(() {
      _previewTimer?.cancel();
      _readinessTimer?.cancel();
    });
    return MobileAutomationComposerState(requestKey: const Uuid().v4());
  }

  void initialize(AutomationDraft draft, {AutomationRecord? editing}) {
    state = MobileAutomationComposerState(
      draft: draft,
      initialDraft: draft,
      editing: editing,
      requestKey: state.requestKey,
      initialized: true,
    );
    unawaited(refreshPreview());
    _scheduleReadiness(immediately: editing != null);
    _requestBranch(draft, seed: true);
  }

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

  /// Applies a change that came from context rather than the user, so it
  /// does not count as an unsaved edit.
  void _seed(AutomationDraft Function(AutomationDraft draft) change) {
    final draft = change(state.draft);
    if (identical(draft, state.draft)) return;
    state = state.copyWith(
      draft: draft,
      initialDraft: change(state.initialDraft),
    );
    _scheduleReadiness();
  }

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
      mobileAutomationReadinessDebounce,
      () => unawaited(checkReadiness()),
    );
  }

  /// Reads an auto-disposed provider once, keeping it alive until it
  /// resolves.
  Future<T> _readOnce<T>(ProviderListenable<Future<T>> provider) async {
    final subscription = ref.listen(provider, (_, _) {});
    try {
      return await subscription.read();
    } finally {
      subscription.close();
    }
  }

  Future<MobileRuntimeAutomationRepository> _repository() =>
      _readOnce(mobileAutomationRepositoryProvider(hostId).future);

  Future<void> refreshPreview() async {
    final draft = state.draft;
    if (draft.whenError != null) return;
    try {
      final preview = await (await _repository()).previewSchedule(
        draft.schedule.toSchedule(timezone: draft.timezone),
      );
      if (preview == null || !ref.mounted || !identical(state.draft, draft)) {
        return;
      }
      state = state.copyWith(preview: () => preview);
      final zone = preview.timezone;
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
    state = state.copyWith(checking: true);
    try {
      final repository = await _repository();
      final readiness = await repository.readiness(<String, Object?>{
        ...draft.toDefinition(supportsReuse: repository.supportsReuse),
        if (state.editing case final editing?) 'id': editing.id,
      });
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
    state = state.copyWith(submitting: true, error: () => null);
    final draft = state.draft;
    try {
      final repository = await _repository();
      final editing = state.editing;
      final definition = draft.toDefinition(
        draft: asDraft,
        supportsReuse: repository.supportsReuse,
      );
      final saved = editing == null
          ? await repository.create(
              definition,
              requestKey: _requestKeyFor(definition),
            )
          : await repository.patch(editing, definition);
      if (ref.mounted) state = state.copyWith(editing: saved);
      if (activate && saved.state == 'draft') {
        await repository.activate(saved);
      }
      ref
          .read(mobileAutomationLastAgentProfileProvider(hostId).notifier)
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

  /// Clears the bound target of the automation being edited, then reloads it
  /// so a later save sends the current revision.
  Future<bool> unbind() async {
    final editing = state.editing;
    if (editing == null) return false;
    try {
      final repository = await _repository();
      await repository.unbind(editing.id);
      final detail = await repository.show(editing.id);
      if (ref.mounted) state = state.copyWith(editing: detail.automation);
      return true;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(error: () => automationErrorMessage(error));
      }
      return false;
    }
  }

  void _requestBranch(AutomationDraft draft, {required bool seed}) {
    final projectId = draft.field(.projectId);
    if (projectId == null ||
        AutomationTargetChoice.of(draft) !=
            AutomationTargetChoice.projectWorktree ||
        (draft.field(.sourceBranch) ?? '').isNotEmpty ||
        _branchRequestedFor == projectId) {
      return;
    }
    _branchRequestedFor = projectId;
    unawaited(_fillBranch(projectId, seed: seed));
  }

  Future<void> _fillBranch(String projectId, {required bool seed}) async {
    try {
      final branches = await _readOnce(
        mobileAutomationProjectBranchesProvider(hostId, projectId).future,
      );
      if (!ref.mounted) return;
      AutomationDraft fill(AutomationDraft draft) =>
          automationSeedSourceBranch(draft, projectId, branches.initial);
      if (seed) {
        _seed(fill);
      } else if (!identical(fill(state.draft), state.draft)) {
        update(fill);
      }
    } on Object {
      // The branch field falls back to free text when listing fails.
    } finally {
      if (_branchRequestedFor == projectId) _branchRequestedFor = null;
    }
  }
}

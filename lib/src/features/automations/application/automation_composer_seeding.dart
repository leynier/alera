part of 'automation_composer_controller.dart';

/// Fills what the opening context determines but only loads later: the
/// default source branch of a project and a project's only folder.
mixin _AutomationComposerSeeding on _$AutomationComposerController {
  String? _branchRequestedFor;

  void update(AutomationDraft Function(AutomationDraft draft) change);

  void _scheduleReadiness();

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

  Future<void> _fillBranch(String projectId, {required bool seed}) async {
    try {
      final branches = await _readOnce(
        automationProjectBranchesProvider(projectId).future,
      );
      if (!ref.mounted) return;
      AutomationDraft fill(AutomationDraft draft) =>
          automationSeedSourceBranch(draft, projectId, branches.initial);
      if (seed) {
        _seed(fill);
      } else if (!identical(fill(state.draft), state.draft)) {
        update(fill);
      }
    } catch (_) {
      // The branch field falls back to free text when listing fails.
    } finally {
      if (_branchRequestedFor == projectId) _branchRequestedFor = null;
    }
  }

  Future<void> _seedProjectFolder(String projectId) async {
    try {
      final folders = await _readOnce(
        automationProjectCheckoutsProvider(projectId).future,
      );
      if (!ref.mounted) return;
      _seed((draft) => automationSeedProjectFolder(draft, projectId, folders));
    } catch (_) {
      // Without the folder list the user picks a destination themselves.
    }
  }
}

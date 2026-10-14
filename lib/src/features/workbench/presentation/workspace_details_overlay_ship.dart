part of 'workspace_details_overlay.dart';

const String _shipMenuPrefix = 'ship:';

extension on _WorkspaceDetailsOverlayState {
  /// The Ship follow-ups and watch toggles the pull request composer offers,
  /// as a section of the git menu. Picking a follow-up ships with it and
  /// remembers it, like the composer's Ship button.
  List<PopupMenuEntry<String>> _shipMenuSection(
    WorkspaceDetailsState data,
    WorkspacePullRequestScope scope,
    ValueNotifier<PullRequestAgentWatchScope> watchScope,
  ) {
    final repo = data.sourceControl.repositoryState;
    final review = ref
        .read(workspacePullRequestControllerProvider(scope))
        .value;
    final settings = ref.read(settingsControllerProvider);
    return pullRequestShipMenuEntries<String>(
      valueOf: (followUp) => '$_shipMenuPrefix${followUp.name}',
      selected: settings.general.pullRequestShipFollowUp,
      scope: watchScope,
      onScopeChanged: (value) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPullRequestAgentWatchScope(value),
      ),
      enabled:
          settings.aiAssist.enabled &&
          review != null &&
          review.supportsCreation &&
          review.currentBranch != null &&
          !review.isBusy &&
          !repo.hasConflicts &&
          repo.branch != 'HEAD',
    );
  }

  PullRequestShipFollowUp? _shipChoice(String choice) =>
      choice.startsWith(_shipMenuPrefix)
      ? PullRequestShipFollowUp.values.byName(
          choice.substring(_shipMenuPrefix.length),
        )
      : null;

  Future<void> _ship(
    WorkspaceDetailsState data,
    WorkspacePullRequestScope scope,
    PullRequestShipFollowUp followUp,
    PullRequestAgentWatchScope watchScope,
  ) async {
    final settings = ref.read(settingsControllerProvider);
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setPullRequestShipFollowUp(followUp),
    );
    final review = ref
        .read(workspacePullRequestControllerProvider(scope))
        .value;
    final base = review?.suggestedBaseBranch ?? data.defaultBranch;
    if (base.trim().isEmpty) {
      AleraToast.show(
        context,
        message: 'Base branch is required',
        tone: .error,
      );
      return;
    }
    final shipScope = data.sourceControl.status.entries.isEmpty
        ? PullRequestShipScope.staged
        : await showDialog<PullRequestShipScope>(
            context: context,
            builder: (_) => const AleraChoiceDialog<PullRequestShipScope>(
              title: 'Ship Changes?',
              message: 'Ship only staged changes, or stage all changes first and include them in the commit.',
              primaryLabel: 'Ship Staged Changes',
              primaryValue: .staged,
              secondaryLabel: 'Ship All Changes',
              secondaryValue: .all,
              stackedActions: true,
            ),
          );
    if (!mounted || shipScope == null) return;
    final controller = ref.read(
      workspacePullRequestControllerProvider(scope).notifier,
    );
    final draft =
        ref
                .read(workbenchControllerProvider)
                .viewPrefs
                .pullRequestCreateAction ==
            PullRequestCreateAction.draft &&
        !followUp.merges;
    await shipPullRequestWithFollowUp(
      context: context,
      ref: ref,
      controller: controller,
      followUp: followUp,
      watchScope: watchScope,
      ship: () => controller.ship(
        baseBranch: base,
        draft: draft,
        settings: settings.aiAssist,
        scope: shipScope,
      ),
    );
  }
}

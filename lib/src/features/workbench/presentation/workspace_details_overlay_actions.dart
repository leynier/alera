part of 'workspace_details_overlay.dart';

extension on _WorkspaceDetailsOverlayState {
  Future<void> _recoverComparisonBase() async {
    final original = widget.workspace;
    final scope = _scope;
    final controller = ref.read(workbenchControllerProvider.notifier);
    final router = ref.read(gitBackendProvider);
    final git = router is HostRoutedGitBackend
        ? router.forPath(scope.repoPath)
        : router;
    try {
      final branches = await git.listBranches(scope.repoPath);
      if (!mounted) return;
      final choice = await showDialog<WorkspaceBranchChoice>(
        context: context,
        builder: (_) => WorkspaceBranchDialog(
          title: 'Compare Against',
          branches: branches,
          currentBranch: '',
          allowCreate: false,
          allowAutomatic: true,
        ),
      );
      if (choice case WorkspaceSwitchBranch(:final branch)) {
        controller.setWorkspaceComparisonBase(
          original.id,
          scope.repoPath,
          branch.isEmpty ? null : branch,
        );
      }
    } catch (error) {
      if (mounted) {
        AleraToast.show(context, message: error.toString(), tone: .error);
      }
    }
  }

  Future<String?> _menu(List<PopupMenuEntry<String>> entries) {
    final anchor = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final rect = anchor == null
        ? Rect.zero
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: entries,
    );
  }

  Future<void> _detailsOptions() async {
    final choice = await _menu(const [
      AleraDropdownEntry(value: 'host', label: 'Host And Hand Off'),
      AleraDropdownEntry(value: 'open', label: 'Open In'),
    ]);
    if (!mounted) return;
    if (choice == 'host') await _hostMenu();
    if (choice == 'open') await _openMenu();
  }

  Future<void> _hostMenu() async {
    final workspace = widget.workspace;
    final choice = await _menu([
      AleraDropdownEntry(
        value: 'handoff',
        label: 'Hand Off',
        enabled: workspace.isMain,
      ),
    ]);
    if (choice == 'handoff' && mounted) {
      await showHandOffWorkspaceFlow(context, ref, workspace: workspace);
    }
  }

  Future<void> _openMenu() async {
    final workspace = widget.workspace;
    final choice = await _menu([
      AleraDropdownEntry(
        value: 'folder',
        label:
            'Open In ${ref.read(workspaceFolderOpenerProvider).fileManagerLabel}',
        enabled: !workspace.isRemote,
      ),
      const AleraDropdownEntry(value: 'copy', label: 'Copy Path'),
      const AleraDropdownEntry(value: 'browser', label: 'Open In Browser'),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'folder':
        await external_actions.openWorkspaceFolder(context, ref, workspace);
      case 'copy':
        await external_actions.copyWorkspacePath(context, workspace);
      case 'browser':
        await external_actions.openWorkspaceInBrowser(context, ref, workspace);
    }
  }

  Future<void> _branchMenu(WorkspaceDetailsState data) async {
    final workspace = widget.workspace;
    final scope = _scope;
    final source = ref.read(
      workspaceSourceControlControllerProvider(scope.repoPath).notifier,
    );
    final controller = ref.read(workbenchControllerProvider.notifier);
    final reviewController = ref.read(
      workspacePullRequestControllerProvider(scope).notifier,
    );
    final choice = await _menu([
      const AleraDropdownEntry(
        value: 'switch',
        label: 'Switch Or Create Branch',
      ),
      const AleraDropdownEntry(value: 'base', label: 'Compare Against'),
    ]);
    if (!mounted || choice == null) return;
    if (choice == 'base') {
      final selection = await showDialog<WorkspaceBranchChoice>(
        context: context,
        builder: (_) => WorkspaceBranchDialog(
          title: 'Compare Against',
          branches: data.branches,
          currentBranch: data.comparison.baseRef ?? '',
          allowCreate: false,
          allowAutomatic: true,
        ),
      );
      if (selection case WorkspaceSwitchBranch(:final branch)) {
        controller.setWorkspaceComparisonBase(
          workspace.id,
          scope.repoPath,
          branch.isEmpty ? null : branch,
        );
      }
      return;
    }
    final selection = await showDialog<WorkspaceBranchChoice>(
      context: context,
      builder: (_) => WorkspaceBranchDialog(
        branches: data.branches,
        currentBranch: data.sourceControl.repositoryState.branch,
      ),
    );
    if (!mounted || selection == null) return;
    final branch = switch (selection) {
      WorkspaceSwitchBranch(:final branch) => branch,
      WorkspaceCreateBranch(:final branch) => branch,
    };
    if (!await confirmWorkspaceBranchChange(context, workspace, branch)) return;
    try {
      switch (selection) {
        case WorkspaceSwitchBranch():
          await source.checkoutBranch(branch);
        case WorkspaceCreateBranch():
          await source.createAndCheckoutBranch(branch);
      }
      await reviewController.refresh();
    } catch (error) {
      if (mounted) {
        AleraToast.show(context, message: error.toString(), tone: .error);
      }
    }
  }

  Future<void> _gitMenu(
    WorkspaceDetailsState data,
    WorkspacePullRequestScope scope,
  ) async {
    final repo = data.sourceControl.repositoryState;
    final choice = await _menu([
      for (final action in WorkspaceGitQuickAction.values)
        AleraDropdownEntry(
          value: action.name,
          label: action.label,
          enabled:
              !repo.hasConflicts &&
              repo.branch != 'HEAD' &&
              (action == WorkspaceGitQuickAction.commit ||
                  repo.behind == 0 ||
                  (action == WorkspaceGitQuickAction.pull &&
                      repo.ahead == 0)) &&
              (!action.includesCommit || data.sourceControl.hasChanges) &&
              (action == WorkspaceGitQuickAction.commit || data.hasRemote) &&
              (!action.includesPr ||
                  data.pullRequest?.supportsCreation == true) &&
              (action != WorkspaceGitQuickAction.pull || repo.hasUpstream),
        ),
      const PopupMenuDivider(),
      const AleraDropdownEntry(value: 'refresh', label: 'Refresh'),
    ]);
    if (!mounted || choice == null) return;
    if (choice == 'refresh') {
      await ref
          .read(
            workspaceSourceControlControllerProvider(scope.repoPath).notifier,
          )
          .refresh();
      return;
    }
    await _requestAction(
      data,
      WorkspaceGitQuickAction.values.byName(choice),
      scope,
    );
  }

  Future<void> _requestAction(
    WorkspaceDetailsState data,
    WorkspaceGitQuickAction action,
    WorkspacePullRequestScope scope,
  ) async {
    try {
      await _prepareAction(data, action, scope);
    } catch (error) {
      if (mounted) {
        AleraToast.show(context, message: error.toString(), tone: .error);
      }
    }
  }

  Future<void> _prepareAction(
    WorkspaceDetailsState data,
    WorkspaceGitQuickAction action,
    WorkspacePullRequestScope scope,
  ) async {
    final original = widget.workspace;
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final ownerRef = WeakReference(this);
    final router = ref.read(gitBackendProvider);
    final git = router is HostRoutedGitBackend
        ? router.forPath(scope.repoPath)
        : router;
    final assist = ref.read(aiAssistServiceProvider);
    final settings = ref.read(settingsControllerProvider).aiAssist;
    final snapshot = await git.workspaceComparison(scope.repoPath);
    if (!mounted) return;
    if (!snapshot.headRef.startsWith('refs/heads/')) {
      throw StateError('Check out a branch first.');
    }
    final branch = snapshot.headRef.substring('refs/heads/'.length);
    var canceled = false;
    var ownedGeneration = false;
    WorkspaceGitSubmission? submission;
    if (action.includesCommit ||
        action.includesPr ||
        branch == data.defaultBranch) {
      submission = await showDialog<WorkspaceGitSubmission>(
        context: context,
        builder: (dialogContext) => WorkspaceGitSubmissionDialog(
          path: scope.repoPath,
          snapshot: snapshot,
          action: action,
          branch: branch,
          initialTitle: action.includesCommit
              ? ''
              : data.sourceControl.repositoryState.headMessage
                        ?.split('\n')
                        .first ??
                    '',
          sharedCheckout: original.isMain,
          baseBranch: shortWorkspaceBranchRef(
            data.comparison.baseRef ?? data.defaultBranch,
            data.remoteNames,
          ),
          isDefaultBranch: branch == data.defaultBranch,
          provider: data.pullRequest?.identity?.provider,
          onOpenFile: (file) => unawaited(
            showDialog<void>(
              context: dialogContext,
              builder: (_) => WorkspaceComparisonDialog(
                git: git,
                path: scope.repoPath,
                comparison: snapshot,
                initialFile: file,
              ),
            ),
          ),
          onGenerate: !settings.enabled
              ? null
              : (files) async {
                  final patches = <String>[];
                  var size = 0;
                  for (final file in files) {
                    if (canceled) throw const AiAssistCanceledException();
                    if (size >= stagedDiffPromptBudget) break;
                    final diff = await git.workspaceComparisonDiff(
                      scope.repoPath,
                      snapshot,
                      file,
                    );
                    for (final entry in diff.files) {
                      final patch = entry.lines
                          .map((line) => line.text)
                          .join('\n');
                      final bounded =
                          patch.length > stagedDiffPromptBudget - size
                          ? patch.substring(0, stagedDiffPromptBudget - size)
                          : patch;
                      patches.add(bounded);
                      size += bounded.length;
                    }
                  }
                  if (canceled) throw const AiAssistCanceledException();
                  try {
                    final result = await assist.generate(
                      AiAssistRequest(
                        onStarted: () => ownedGeneration = true,
                        operation: .commitMessage,
                        workspacePath: scope.repoPath,
                        settings: settings,
                        commitContext: AiAssistCommitContext(
                          branch: branch,
                          stagedSummary: files.join('\n'),
                          stagedPatch: patches.join('\n'),
                        ),
                      ),
                    );
                    return result.text;
                  } finally {
                    ownedGeneration = false;
                  }
                },
        ),
      );
      canceled = true;
      if (ownedGeneration) assist.cancel(scope.repoPath, .commitMessage);
    } else {
      submission = WorkspaceGitSubmission(
        path: scope.repoPath,
        snapshot: snapshot,
        action: action,
        files: const [],
        message: '',
      );
    }
    if (submission != null) {
      _submitWorkspaceGitJob(
        submission,
        scope,
        original,
        container,
        navigator,
        ownerRef,
      );
    }
  }

  Future<void> _execute(
    WorkspaceGitSubmission submission,
    WorkspacePullRequestScope scope,
  ) async {
    if (_running) return;
    _submitWorkspaceGitJob(
      submission,
      scope,
      widget.workspace,
      ProviderScope.containerOf(context, listen: false),
      Navigator.of(context),
      WeakReference(this),
    );
  }
}

void _submitWorkspaceGitJob(
  WorkspaceGitSubmission submission,
  WorkspacePullRequestScope scope,
  Workspace original,
  ProviderContainer container,
  NavigatorState navigator,
  WeakReference<_WorkspaceDetailsOverlayState> ownerRef,
) {
  final jobs = container.read(backgroundOperationsProvider.notifier);
  final operationKey = 'workspace-git:${original.hostId}:${scope.repoPath}';
  void submit() {
    final started = jobs.submit(
      operationKey: operationKey,
      title: '${original.name}: ${submission.action.label}',
      action: () async {
        final progress = container.read(
          workspaceGitProgressProvider(scope).notifier,
        );
        final id = progress.start(retry: submit);
        String? error;
        try {
          error = await runWorkspaceGitSubmissionJob(
            container,
            original,
            scope,
            submission,
            onPhase: (phase) => progress.update(id, phase: phase),
            onOutput: (line) => progress.update(id, output: line),
          );
        } catch (failure) {
          error = '${submission.completedSummary}$failure';
        }
        progress.finish(id, error: error);
        final owner = ownerRef.target;
        if (owner != null &&
            owner.mounted &&
            owner.widget.workspace.id == original.id &&
            owner.widget.workspace.hostId == original.hostId &&
            (owner.widget.sourceControlScope?.path ??
                    owner.widget.workspace.path) ==
                scope.repoPath) {
          owner._changeState(() {
            owner._running = false;
            owner._pending =
                error != null &&
                    (submission.commitCompleted || submission.branchCreated)
                ? submission
                : null;
          });
        }
        return error;
      },
      onSuccess: () => AleraToast.publish(
        message: '${submission.action.label} completed',
        tone: .success,
      ),
      restore: () {
        if (!navigator.mounted) return;
        unawaited(
          showDialog<bool>(
            context: navigator.context,
            builder: (_) => AleraConfirmDialog(
              title: submission.pendingLabel,
              message:
                  '${submission.completedSummary}Continue the remaining action in ${original.name}?',
              confirmLabel: 'Continue',
            ),
          ).then((confirmed) {
            if (confirmed == true) {
              submit();
            }
          }),
        );
      },
    );
    final owner = ownerRef.target;
    if (started && owner != null && owner.mounted) {
      owner._changeState(() {
        owner._running = true;
        owner._pending = null;
      });
    } else if (!started) {
      AleraToast.publish(
        message: 'Another Git action is already running for this workspace.',
        tone: .info,
      );
    }
  }

  submit();
}

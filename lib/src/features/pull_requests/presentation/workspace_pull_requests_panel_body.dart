part of 'workspace_pull_requests_panel.dart';

class const _PullRequestBody({
  required final String repoPath,
  required final WorkspacePullRequestState state,
  required final PullRequestCreateAction createAction,
  required final AiAssistSettings aiAssistSettings,
  required final WorkspacePullRequestController controller,
  required final Set<String> localWorkspaceBranches,
  required final List<ReviewStackWorkspaceCandidate> stackWorkspaceCandidates,
  required final Future<void> Function(String branch)? onOpenWorkspaceBranch,
  required final Future<void> Function(String url) onOpenUrl,
  required final ValueChanged<HostedReview>? onOpenDiff,
  required final ValueChanged<PullRequestCreateAction> onCreateActionChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _Header(
          refreshing: state.isRefreshing,
          enabled: !state.isBusy,
          onRefresh: controller.refresh,
        ),
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        Expanded(child: _content(context)),
      ],
    );
  }

  Widget _content(BuildContext context) {
    if (state.unavailableReason != null) {
      return _unavailable(state.unavailableReason!);
    }
    if (state.authStatus == ForgeAuthStatus.cliMissing) {
      return _MessageBody(
        icon: AleraIcons.error,
        title: 'CLI not found',
        message: 'Install `${_providerCli()}` and ensure it is on your PATH.',
      );
    }
    if (state.authStatus == ForgeAuthStatus.notAuthenticated) {
      return _MessageBody(
        icon: AleraIcons.error,
        title: 'Not authenticated',
        message: 'Run `${_authCommand()}` to sign in, then refresh.',
        action: OutlinedButton(
          onPressed: controller.refresh,
          child: const Text('Refresh'),
        ),
      );
    }
    final review = state.review;
    if (review != null) {
      return PullRequestReviewView(
        review: review,
        stack: state.stack,
        stackSupported: state.stackSupported,
        stackErrorMessage: state.stackErrorMessage,
        localWorkspaceBranches: localWorkspaceBranches,
        stackWorkspaceCandidates: stackWorkspaceCandidates,
        stackDefaultDraft: createAction == PullRequestCreateAction.draft,
        checks: state.checks,
        comments: state.comments,
        baseBranches: state.baseBranches,
        mergeMethods: state.mergeMethods,
        canCloseReview: state.canCloseReview,
        canChangeDraftStatus: state.canChangeDraftStatus,
        canComment: state.canComment,
        canEditComments: state.canEditComments,
        savingCommentIds: state.savingCommentIds,
        action: state.action,
        onOpenUrl: onOpenUrl,
        onOpenDiff: onOpenDiff == null ? null : () => onOpenDiff!(review),
        onOpenWorkspaceBranch: onOpenWorkspaceBranch,
        onUnlink: controller.unlink,
        onLinkStack: controller.linkReviewStack,
        onCreateStackFromWorkspaces: controller.createReviewStackFromWorkspaces,
        onMerge: controller.mergeReview,
        onClose: controller.closeReview,
        onDraftStatusChanged: controller.setReviewDraft,
        onAddComment: controller.addReviewComment,
        onToggleTask: controller.toggleReviewCommentTask,
        onUpdate: controller.updateReview,
        onLoadCheckDetails: controller.loadCheckDetails,
      );
    }
    final canCreate = state.supportsCreation && state.currentBranch != null;
    final canCreateStack =
        state.stackSupported &&
        state.isAuthenticated &&
        state.currentBranch?.trim().isNotEmpty == true &&
        stackWorkspaceCandidates.length >= 2 &&
        stackWorkspaceCandidates.any((candidate) => candidate.current);
    return PullRequestComposer(
      repoPath: repoPath,
      headBranch: state.currentBranch,
      baseBranches: state.baseBranches,
      suggestedBaseBranch: state.suggestedBaseBranch ?? 'main',
      canCreate: canCreate,
      busy: state.isBusy,
      suggestedReview: state.suggestedReview,
      createAction: createAction,
      canCreateStack: canCreateStack,
      creatingStack: state.action == PullRequestAction.createStack,
      shipping: state.action == PullRequestAction.ship,
      onCreate: (draft) {
        final identity = state.identity;
        final head = state.currentBranch;
        if (identity == null || head == null) {
          return;
        }
        controller.createReview(
          CreateReviewInput(
            provider: identity.provider,
            title: draft.title,
            baseBranch: draft.baseBranch,
            headBranch: head,
            body: draft.body,
            draft: draft.draft,
          ),
        );
      },
      onShip:
          ({
            required String baseBranch,
            required bool draft,
            required PullRequestShipScope scope,
          }) async {
            await controller.ship(
              baseBranch: baseBranch,
              draft: draft,
              settings: aiAssistSettings,
              scope: scope,
            );
          },
      onCreateStack: (draft) =>
          _openWorkspaceStackDialog(context, currentDraft: draft),
      onLink: controller.link,
      onCreateActionChanged: onCreateActionChanged,
    );
  }

  Future<void> _openWorkspaceStackDialog(
    BuildContext context, {
    required CreateReviewDraft currentDraft,
  }) async {
    final request = await showDialog<ReviewStackWorkspaceRequest>(
      context: context,
      builder: (_) => PullRequestStackWorkspaceDialog(
        currentTitle: currentDraft.title,
        currentBody: currentDraft.body,
        currentDraft: currentDraft.draft,
        candidates: stackWorkspaceCandidates,
        baseBranches: state.baseBranches,
        suggestedBaseBranch: currentDraft.baseBranch,
        defaultDraft: currentDraft.draft,
      ),
    );
    if (request == null || !context.mounted) {
      return;
    }
    await controller.createReviewStackFromWorkspaces(request);
  }

  Widget _unavailable(PullRequestUnavailableReason reason) {
    return switch (reason) {
      PullRequestUnavailableReason.noRemote => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'No remote',
        message: 'This repository has no remote to detect a provider from.',
      ),
      PullRequestUnavailableReason.undetectable => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'Provider not detected',
        message: 'Could not detect the git hosting provider. Set it in project settings.',
      ),
      PullRequestUnavailableReason.unsupported => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'Unsupported provider',
        message: 'This hosting provider is not supported yet.',
      ),
    };
  }

  String _providerCli() => switch (state.identity?.provider) {
    GitHostingProvider.github => 'gh',
    GitHostingProvider.gitlab => 'glab',
    GitHostingProvider.azureDevops => 'az',
    null => 'the provider CLI',
  };

  String _authCommand() {
    final identity = state.identity;
    return switch (identity?.provider) {
      GitHostingProvider.github =>
        identity!.host == 'github.com'
            ? 'gh auth login'
            : 'gh auth login --hostname ${identity.host}',
      GitHostingProvider.gitlab =>
        identity!.host == 'gitlab.com'
            ? 'glab auth login'
            : 'glab auth login --hostname ${identity.host}',
      GitHostingProvider.azureDevops => 'az login',
      null => 'the provider CLI login command',
    };
  }
}

class const _Header({
  required final bool refreshing,
  required final bool enabled,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
          child: Row(
            children: <Widget>[
              Text(
                'Pull Request',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
              const Spacer(),
              if (refreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                AleraIconButton(
                  tooltip: 'Refresh',
                  icon: AleraIcons.refresh,
                  onPressed: enabled ? onRefresh : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _ErrorBanner({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: .infinity,
      color: AleraTokens.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
      ),
    );
  }
}

class const _MessageBody({
  required final IconData icon,
  required final String message,
  final String? title,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

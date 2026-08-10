import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_composer.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature-level wrapper mounting the pull-request panel for a workspace. Reads
/// the provider override + controller and renders the presentational body.
class WorkspacePullRequestsPanel extends ConsumerWidget {
  const WorkspacePullRequestsPanel({
    super.key,
    required this.workspace,
    required this.repoPath,
    this.gitDiffRoot,
  });

  final Workspace workspace;

  /// The git repository Source Control controls for this workspace - the
  /// workspace path for git projects, or a designated git subfolder for Folder
  /// workspaces (`WorkspaceSourceControlScope.path`).
  final String repoPath;

  /// The Source Control root relative to the workspace, when [repoPath] points
  /// at a designated repository inside a Folder workspace.
  final String? gitDiffRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrideAsync = ref.watch(
      effectiveHostingProviderOverrideProvider(workspace.projectId),
    );
    return overrideAsync.when(
      loading: _loading,
      error: (error, _) =>
          _MessageBody(icon: AleraIcons.error, message: error.toString()),
      data: (override) {
        final scope = WorkspacePullRequestScope(
          workspaceId: workspace.id,
          repoPath: repoPath,
          branch: workspace.branch,
          sourceBranch: workspace.sourceBranch,
          providerOverride: override,
        );
        return _VisiblePullRequestsPanel(
          key: ValueKey<WorkspacePullRequestScope>(scope),
          workspace: workspace,
          scope: scope,
          repoPath: repoPath,
          gitDiffRoot: gitDiffRoot,
        );
      },
    );
  }

  static Widget _loading() => const Center(child: CircularProgressIndicator());
}

class _VisiblePullRequestsPanel extends ConsumerStatefulWidget {
  const _VisiblePullRequestsPanel({
    super.key,
    required this.scope,
    required this.workspace,
    required this.repoPath,
    this.gitDiffRoot,
  });

  final WorkspacePullRequestScope scope;
  final Workspace workspace;
  final String repoPath;
  final String? gitDiffRoot;

  @override
  ConsumerState<_VisiblePullRequestsPanel> createState() =>
      _VisiblePullRequestsPanelState();
}

class _VisiblePullRequestsPanelState
    extends ConsumerState<_VisiblePullRequestsPanel> {
  late final WorkspacePullRequestController _controller;
  bool _openingDiff = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(
      workspacePullRequestControllerProvider(widget.scope).notifier,
    );
    _controller.attachPanel();
  }

  @override
  void dispose() {
    _controller.detachPanel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      workspacePullRequestControllerProvider(widget.scope),
    );
    final createAction = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.viewPrefs.pullRequestCreateAction,
      ),
    );
    return async.when(
      loading: WorkspacePullRequestsPanel._loading,
      error: (error, _) =>
          _MessageBody(icon: AleraIcons.error, message: error.toString()),
      data: (state) => _PullRequestBody(
        repoPath: widget.repoPath,
        state: state,
        createAction: createAction,
        controller: _controller,
        onOpenUrl: (url) =>
            ref.read(externalUriLauncherProvider).open(Uri.parse(url)),
        onOpenDiff: _openingDiff ? null : _openDiff,
        onCreateActionChanged: (action) => ref
            .read(workbenchControllerProvider.notifier)
            .setPullRequestCreateAction(action),
      ),
    );
  }

  Future<void> _openDiff(HostedReview review) async {
    final baseRef = review.baseBranch?.trim() ?? '';
    final headRef = review.headSha?.trim() ?? '';
    if (baseRef.isEmpty || headRef.isEmpty) {
      AleraToast.show(
        context,
        message:
            'The linked pull request does not expose a comparable branch range.',
        tone: AleraToastTone.error,
      );
      return;
    }
    setState(() => _openingDiff = true);
    try {
      final range = await ref
          .read(gitBackendProvider)
          .rangeContext(widget.repoPath, baseRef: baseRef, headRef: headRef);
      final mergeBase = range.mergeBase;
      final headOid = range.headOid ?? headRef;
      if (mergeBase == null || mergeBase.isEmpty) {
        throw StateError('The pull request merge base could not be resolved.');
      }
      if (!mounted) {
        return;
      }
      await ref
          .read(workbenchControllerProvider.notifier)
          .openGitPullRequestDiffTab(
            workspace: widget.workspace,
            gitDiffRoot: widget.gitDiffRoot,
            pullRequestNumber: review.number,
            commitOid: headOid,
            parentOid: mergeBase,
            subject: review.title,
          );
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Could not open the pull request diff: $error',
          tone: AleraToastTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingDiff = false);
      }
    }
  }
}

class _PullRequestBody extends StatelessWidget {
  const _PullRequestBody({
    required this.repoPath,
    required this.state,
    required this.createAction,
    required this.controller,
    required this.onOpenUrl,
    required this.onOpenDiff,
    required this.onCreateActionChanged,
  });

  final String repoPath;
  final WorkspacePullRequestState state;
  final PullRequestCreateAction createAction;
  final WorkspacePullRequestController controller;
  final Future<void> Function(String url) onOpenUrl;
  final ValueChanged<HostedReview>? onOpenDiff;
  final ValueChanged<PullRequestCreateAction> onCreateActionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(
          refreshing: state.isRefreshing,
          enabled: !state.isBusy,
          onRefresh: controller.refresh,
        ),
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
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
        onUnlink: controller.unlink,
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
    return PullRequestComposer(
      repoPath: repoPath,
      headBranch: state.currentBranch,
      baseBranches: state.baseBranches,
      suggestedBaseBranch: state.suggestedBaseBranch ?? 'main',
      canCreate: canCreate,
      busy: state.isBusy,
      suggestedReview: state.suggestedReview,
      createAction: createAction,
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
      onLink: controller.link,
      onCreateActionChanged: onCreateActionChanged,
    );
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
        message:
            'Could not detect the git hosting provider. Set it in project settings.',
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

class _Header extends StatelessWidget {
  const _Header({
    required this.refreshing,
    required this.enabled,
    required this.onRefresh,
  });

  final bool refreshing;
  final bool enabled;
  final VoidCallback onRefresh;

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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: AleraTokens.error.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.icon,
    required this.message,
    this.title,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? title;
  final Widget? action;

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

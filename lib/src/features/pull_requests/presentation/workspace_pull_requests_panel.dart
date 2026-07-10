import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_icon.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_create_dialog.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_link_dialog.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
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
  });

  final Workspace workspace;

  /// The git repository Source Control controls for this workspace — the
  /// workspace path for git projects, or a designated git subfolder for Folder
  /// workspaces (`WorkspaceSourceControlScope.path`).
  final String repoPath;

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
          providerOverride: override,
        );
        final async = ref.watch(workspacePullRequestControllerProvider(scope));
        return async.when(
          loading: _loading,
          error: (error, _) =>
              _MessageBody(icon: AleraIcons.error, message: error.toString()),
          data: (state) => _PullRequestBody(
            workspace: workspace,
            state: state,
            controller: ref.read(
              workspacePullRequestControllerProvider(scope).notifier,
            ),
            onOpenUrl: (url) =>
                ref.read(externalUriLauncherProvider).open(Uri.parse(url)),
          ),
        );
      },
    );
  }

  static Widget _loading() => const Center(child: CircularProgressIndicator());
}

class _PullRequestBody extends StatelessWidget {
  const _PullRequestBody({
    required this.workspace,
    required this.state,
    required this.controller,
    required this.onOpenUrl,
  });

  final Workspace workspace;
  final WorkspacePullRequestState state;
  final WorkspacePullRequestController controller;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(busy: state.isBusy, onRefresh: controller.refresh),
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
      return const _MessageBody(
        icon: AleraIcons.error,
        title: 'CLI Not Found',
        message:
            'Install the provider CLI (gh or az) and ensure it is on your PATH.',
      );
    }
    if (state.authStatus == ForgeAuthStatus.notAuthenticated) {
      return _MessageBody(
        icon: AleraIcons.error,
        title: 'Not Authenticated',
        message:
            'Sign in with the provider CLI (for example `gh auth login` or `az login`), then refresh.',
        action: OutlinedButton(
          onPressed: controller.refresh,
          child: const Text('Refresh'),
        ),
      );
    }
    final review = state.review;
    if (review != null) {
      return _ReviewView(
        review: review,
        checks: state.checks,
        rollup: state.checksRollup,
        onOpenUrl: onOpenUrl,
        onUnlink: controller.unlink,
      );
    }
    return _EmptyReview(
      workspace: workspace,
      canCreate: state.supportsCreation && state.currentBranch != null,
      providerLabel: state.identity?.provider.label,
      onLink: () => _link(context),
      onCreate: () => _create(context),
    );
  }

  Widget _unavailable(PullRequestUnavailableReason reason) {
    return switch (reason) {
      PullRequestUnavailableReason.noRemote => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'No Remote',
        message: 'This repository has no remote to detect a provider from.',
      ),
      PullRequestUnavailableReason.undetectable => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'Provider Not Detected',
        message:
            'Could not detect the git hosting provider. Set it in Project settings.',
      ),
      PullRequestUnavailableReason.unsupported => const _MessageBody(
        icon: AleraIcons.gitPullRequest,
        title: 'Unsupported Provider',
        message: 'This hosting provider is not supported yet.',
      ),
    };
  }

  Future<void> _link(BuildContext context) async {
    final reference = await showLinkReviewDialog(context);
    if (reference != null) {
      await controller.link(reference);
    }
  }

  Future<void> _create(BuildContext context) async {
    final identity = state.identity;
    final head = state.currentBranch;
    if (identity == null || head == null) {
      return;
    }
    final draft = await showCreateReviewDialog(
      context,
      defaultTitle: head,
      defaultBaseBranch: workspace.sourceBranch ?? 'main',
      headBranch: head,
    );
    if (draft == null) {
      return;
    }
    await controller.createReview(
      CreateReviewInput(
        provider: identity.provider,
        title: draft.title,
        baseBranch: draft.baseBranch,
        headBranch: head,
        body: draft.body,
        draft: draft.draft,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.busy, required this.onRefresh});

  final bool busy;
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
                'Checks',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                AleraIconButton(
                  tooltip: 'Refresh',
                  icon: AleraIcons.refresh,
                  onPressed: onRefresh,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.review,
    required this.checks,
    required this.rollup,
    required this.onOpenUrl,
    required this.onUnlink,
  });

  final HostedReview review;
  final List<ReviewCheck> checks;
  final ReviewChecksRollup rollup;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space12),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              AleraIcons.gitPullRequest,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space6),
            Text(
              '#${review.number}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AleraTokens.foreground,
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            _StateChip(state: review.state),
            const Spacer(),
            AleraIconButton(
              tooltip: 'Open In Browser',
              icon: AleraIcons.external,
              onPressed: () => onOpenUrl(review.url),
            ),
            AleraIconButton(
              tooltip: 'Unlink',
              icon: AleraIcons.link,
              onPressed: onUnlink,
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        Text(review.title, style: theme.textTheme.bodyMedium),
        if (review.author != null || review.headBranch != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            <String>[
              if (review.author != null) review.author!,
              if (review.headBranch != null) review.headBranch!,
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
        const SizedBox(height: AleraTokens.space16),
        Text(
          checks.isEmpty ? 'Checks' : 'Checks (${checks.length})',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        if (checks.isEmpty)
          Text(
            'No Checks Reported',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          )
        else
          for (final check in checks)
            _CheckRow(check: check, onOpenUrl: onOpenUrl),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.onOpenUrl});

  final ReviewCheck check;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = check.url;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          PullRequestCheckIcon(
            status: check.status,
            conclusion: check.conclusion,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              check.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (url != null && url.isNotEmpty)
            AleraIconButton(
              tooltip: 'Open Check',
              icon: AleraIcons.external,
              onPressed: () => onOpenUrl(url),
            ),
        ],
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({
    required this.workspace,
    required this.canCreate,
    required this.providerLabel,
    required this.onLink,
    required this.onCreate,
  });

  final Workspace workspace;
  final bool canCreate;
  final String? providerLabel;
  final VoidCallback onLink;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: AleraIcons.gitPullRequest,
      title: 'No Pull Request',
      message: providerLabel == null
          ? 'This branch has no linked pull request.'
          : 'This branch has no $providerLabel pull request.',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          if (canCreate)
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(AleraIcons.gitPullRequest, size: 16),
              label: const Text('Create Pull Request'),
            ),
          OutlinedButton.icon(
            onPressed: onLink,
            icon: const Icon(AleraIcons.link, size: 16),
            label: const Text('Link Existing'),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final HostedReviewState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      HostedReviewState.open => ('Open', AleraTokens.success),
      HostedReviewState.draft => ('Draft', AleraTokens.foregroundMuted),
      HostedReviewState.merged => ('Merged', AleraTokens.accent),
      HostedReviewState.closed => ('Closed', AleraTokens.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
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

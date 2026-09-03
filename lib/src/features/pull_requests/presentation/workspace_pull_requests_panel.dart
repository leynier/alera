import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_composer.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_workspace_dialog.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_request_stack_candidates.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_pull_requests_panel_body.dart';

/// Feature-level wrapper mounting the pull-request panel for a workspace. Reads
/// the provider override + controller and renders the presentational body.
class const WorkspacePullRequestsPanel({
  super.key,
  required final Workspace workspace,
  required this.repoPath,
  this.gitDiffRoot,
}) extends ConsumerWidget {
  /// The git repository Source Control controls for this workspace - the
  /// workspace path for git projects, or a designated git subfolder for Folder
  /// workspaces (`WorkspaceSourceControlScope.path`).
  final String repoPath;

  /// The Source Control root relative to the workspace, when [repoPath] points
  /// at a designated repository inside a Folder workspace.
  final String? gitDiffRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localContext = ref.watch(
      workbenchControllerProvider.select((state) {
        Project? project;
        for (final candidate in state.projects) {
          if (candidate.id == workspace.projectId) {
            project = candidate;
            break;
          }
        }
        return (
          project: project,
          workspaces: state.workspacesFor(workspace.projectId),
        );
      }),
    );
    final workspaceByBranch = <String, Workspace>{};
    for (final candidate in localContext.workspaces) {
      final branch = candidate.branch?.trim();
      if (!candidate.isActive || branch == null || branch.isEmpty) {
        continue;
      }
      workspaceByBranch.putIfAbsent(branch, () => candidate);
    }
    final stackWorkspaceCandidates = buildReviewStackWorkspaceCandidates(
      workspaces: localContext.workspaces,
      currentWorkspaceId: workspace.id,
      currentRepoPath: repoPath,
    );
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
          workspaceByBranch: workspaceByBranch,
          stackWorkspaceCandidates: stackWorkspaceCandidates,
          onOpenWorkspaceBranch: localContext.project == null
              ? null
              : (branch) async {
                  final target = workspaceByBranch[branch];
                  if (target == null) {
                    return;
                  }
                  await ref
                      .read(workbenchControllerProvider.notifier)
                      .selectWorkspace(
                        project: localContext.project!,
                        workspace: target,
                      );
                },
        );
      },
    );
  }

  static Widget _loading() => const Center(child: CircularProgressIndicator());
}

class const _VisiblePullRequestsPanel({
  super.key,
  required final WorkspacePullRequestScope scope,
  required final Workspace workspace,
  required final String repoPath,
  final String? gitDiffRoot,
  required final Map<String, Workspace> workspaceByBranch,
  required final List<ReviewStackWorkspaceCandidate> stackWorkspaceCandidates,
  required final Future<void> Function(String branch)? onOpenWorkspaceBranch,
}) extends ConsumerStatefulWidget {
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
    final aiAssistSettings = ref.watch(
      settingsControllerProvider.select((settings) => settings.aiAssist),
    );
    return async.when(
      loading: WorkspacePullRequestsPanel._loading,
      error: (error, _) =>
          _MessageBody(icon: AleraIcons.error, message: error.toString()),
      data: (state) {
        final candidates = applyLiveReviewStackWorkspaceBranch(
          candidates: widget.stackWorkspaceCandidates,
          branch: state.currentBranch,
        );
        return _PullRequestBody(
          repoPath: widget.repoPath,
          state: state,
          createAction: createAction,
          aiAssistSettings: aiAssistSettings,
          controller: _controller,
          localWorkspaceBranches: widget.workspaceByBranch.keys.toSet(),
          stackWorkspaceCandidates: candidates,
          onOpenWorkspaceBranch: widget.onOpenWorkspaceBranch,
          onOpenUrl: (url) =>
              ref.read(externalUriLauncherProvider).open(Uri.parse(url)),
          onOpenDiff: _openingDiff ? null : _openDiff,
          onCreateActionChanged: (action) => ref
              .read(workbenchControllerProvider.notifier)
              .setPullRequestCreateAction(action),
        );
      },
    );
  }

  Future<void> _openDiff(HostedReview review) async {
    final baseRef = review.baseBranch?.trim() ?? '';
    final headRef = review.headSha?.trim() ?? '';
    if (baseRef.isEmpty || headRef.isEmpty) {
      AleraToast.show(
        context,
        message: 'The linked pull request does not expose a comparable branch range.',
        tone: .error,
      );
      return;
    }
    setState(() => _openingDiff = true);
    final backend = ref.read(gitBackendProvider);
    GitHostedReviewRange? retainedRange;
    var handedToWorkbench = false;
    try {
      final remote = preferredHostingRemoteName(
        await backend.listRemotes(widget.repoPath),
      );
      if (remote == null) {
        throw StateError('The pull request remote could not be resolved.');
      }
      final objects = await backend.fetchHostedReviewRange(
        path: widget.repoPath,
        remote: remote,
        baseBranch: baseRef,
        headSha: headRef,
        headRemote: review.headRepositoryUrl,
        comparisonBaseSha: review.comparisonBaseSha,
        mergeCommitSha: review.mergeCommitSha,
        reviewRef: switch (review.provider) {
          GitHostingProvider.github => 'refs/pull/${review.number}/head',
          GitHostingProvider.gitlab =>
            'refs/merge-requests/${review.number}/head',
          GitHostingProvider.azureDevops =>
            review.headBranch == null || review.headBranch!.trim().isEmpty
                ? null
                : 'refs/heads/${review.headBranch!.trim()}',
        },
      );
      retainedRange = objects;
      final range = await backend.rangeContext(
        widget.repoPath,
        baseRef: objects.baseOid,
        headRef: objects.headOid,
      );
      final mergeBase = range.mergeBase;
      final headOid = range.headOid ?? headRef;
      if (mergeBase == null || mergeBase.isEmpty) {
        throw StateError('The pull request merge base could not be resolved.');
      }
      if (!mounted) {
        return;
      }
      handedToWorkbench = true;
      await ref
          .read(workbenchControllerProvider.notifier)
          .openGitPullRequestDiffTab(
            workspace: widget.workspace,
            gitDiffRoot: widget.gitDiffRoot,
            pullRequestNumber: review.number,
            commitOid: headOid,
            parentOid: mergeBase,
            retentionId: objects.retentionId,
            subject: review.title,
          );
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Could not open the pull request diff: $error',
          tone: .error,
        );
      }
    } finally {
      if (!handedToWorkbench && retainedRange != null) {
        try {
          await backend.releaseHostedReviewRange(
            path: widget.repoPath,
            retentionId: retainedRange.retentionId,
          );
        } catch (_) {
          // The original open failure is more useful than a cleanup failure.
        }
      }
      if (mounted) {
        setState(() => _openingDiff = false);
      }
    }
  }
}

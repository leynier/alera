import 'package:alera/src/features/error_reporting/presentation/action_failure_toast.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';

import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_review_row.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_review_action.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_action_confirmations.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_agent_dispatch.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_review_launcher.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:alera/src/design_system/menus/alera_menu_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceDetailsReviewRows({
  super.key,
  required this.scope,
  this.compact = false,
}) extends ConsumerStatefulWidget {
  final WorkspacePullRequestScope scope;
  final bool compact;
  @override
  ConsumerState<WorkspaceDetailsReviewRows> createState() =>
      _WorkspaceDetailsReviewRowsState();
}

class _WorkspaceDetailsReviewRowsState
    extends ConsumerState<WorkspaceDetailsReviewRows> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final state = ref
        .watch(workspacePullRequestControllerProvider(widget.scope))
        .value;
    final review = state?.review;
    if (state == null || review == null) return const SizedBox.shrink();
    final seen = <int>{review.number};
    final others =
        state.stack?.entries
            .where((entry) => seen.add(entry.review.number))
            .toList() ??
        [];
    others.sort((a, b) => a.position.compareTo(b.position));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(review, state, primary: true),
        if (_expanded)
          for (final entry in others) _row(entry.review, state, primary: false),
        if (others.isNotEmpty) _stackToggle(others.length),
        if (state.errorMessage != null) _error(state.errorMessage!),
      ],
    );
  }

  Widget _stackToggle(int count) {
    final label = '${_expanded ? 'Hide' : 'Show'} Stack ($count)';
    return AleraWorkspaceDetailControl(
      tooltip: label,
      onPressed: () => setState(() => _expanded = !_expanded),
      child: Row(
        children: [
          AleraWorkspaceDetailLeading(
            child: Icon(_expanded ? AleraIcons.remove : AleraIcons.add),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(String message) => Tooltip(
    message: message,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AleraWorkspaceDetailLeading(
            child: Icon(AleraIcons.error, color: AleraTokens.error),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.error),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(
    HostedReview review,
    WorkspacePullRequestState state, {
    required bool primary,
  }) {
    final action = resolveWorkspaceReviewAction(state);
    final color = switch (review.state) {
      HostedReviewState.open => AleraTokens.success,
      HostedReviewState.merged => AleraTokens.accent,
      HostedReviewState.closed => AleraTokens.error,
      HostedReviewState.draft => AleraTokens.foregroundMuted,
    };
    final checks = state.checksLoaded
        ? '${state.checks.length} Checks'
        : 'Checks';
    final checkSummary = !state.checksLoaded
        ? 'Checks unavailable'
        : switch (state.checksRollup) {
            .none => 'No checks',
            .success => '${state.checks.length} checks passed',
            .failure => 'Checks failed',
            .pending => 'Checks running',
          };
    final checkColor = switch (state.checksRollup) {
      .failure => AleraTokens.error,
      .success => AleraTokens.success,
      .pending => AleraTokens.warning,
      .none => AleraTokens.foregroundMuted,
    };
    final checkIcon = !state.checksLoaded
        ? AleraIcons.checks
        : switch (state.checksRollup) {
            .failure => AleraIcons.cancel,
            .success => AleraIcons.success,
            .pending => AleraIcons.loading,
            .none => AleraIcons.checks,
          };
    final pendingLabel = state.isRefreshing
        ? null
        : switch (state.action) {
            .merge || .mergeStack => 'Merging…',
            .draftStatus => 'Updating…',
            _ => null,
          };
    return AleraWorkspaceReviewRow(
      label: '#${review.number}: ${review.title}',
      stateLabel: switch (review.state) {
        .open => 'Open',
        .draft => 'Draft',
        .merged => 'Merged',
        .closed => 'Closed',
      },
      stateIcon: switch (review.state) {
        .merged => AleraIcons.gitMerge,
        .closed => AleraIcons.gitPullRequestClosed,
        .draft => AleraIcons.gitPullRequestDraft,
        .open => AleraIcons.gitPullRequest,
      },
      stateColor: color,
      tooltip:
          '#${review.number}: ${review.title}\n${review.state.name}\n${review.headBranch ?? '?'} → ${review.baseBranch ?? '?'}${primary ? '\n$checkSummary\n${action.hint ?? ''}' : ''}',
      onOpen: () =>
          revealWorkspaceReview(ref, widget.scope.workspaceId, review.number),
      onMenu: (anchor) => unawaited(_menu(review, anchor)),
      compact: widget.compact,
      checksLabel: primary ? checks : null,
      checksIcon: checkIcon,
      checksColor: checkColor,
      onChecks: primary ? () => unawaited(_checks(state)) : null,
      actionLabel: !primary ? null : action.action?.label ?? pendingLabel,
      actionHint: action.hint,
      actionCritical:
          action.action == WorkspaceReviewAction.resolve ||
          action.action == WorkspaceReviewAction.fix,
      actionPending: primary && action.action == null && pendingLabel != null,
      onAction: primary && action.action != null
          ? () => unawaited(_action(state, action.action!))
          : null,
    );
  }

  Future<void> _menu(HostedReview review, Rect anchor) async {
    final scope = widget.scope;
    final launcher = ref.read(externalUriLauncherProvider);
    final choice = await showMenu<String>(
      context: context,
      position: aleraMenuBelow(context, anchor),
      items: const [
        AleraDropdownEntry(
          value: 'panel',
          label: 'Open PR Panel',
          leading: Icon(
            AleraIcons.gitPullRequest,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        AleraDropdownEntry(
          value: 'browser',
          label: 'Open In Browser',
          leading: Icon(
            AleraIcons.external,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'panel') {
      revealWorkspaceReview(ref, scope.workspaceId, review.number);
    }
    if (choice == 'browser') {
      await _safe(() => launcher.open(Uri.parse(review.url)));
    }
  }

  Future<void> _checks(WorkspacePullRequestState state) async {
    final controller = ref.read(
      workspacePullRequestControllerProvider(widget.scope).notifier,
    );
    final launcher = ref.read(externalUriLauncherProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('PR #${state.review!.number} Checks'),
        content: SizedBox(
          width: AleraTokens.dialogWidth,
          child: SingleChildScrollView(
            child: state.checksLoaded
                ? PullRequestCheckList(
                    checks: state.checks,
                    onOpenUrl: (url) => launcher.open(Uri.parse(url)),
                    onLoadDetails: controller.loadCheckDetails,
                  )
                : Text(
                    state.checksErrorMessage ??
                        'Checks have not loaded. Refresh the PR.',
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(controller.refresh());
            },
            child: const Text('Refresh'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _action(
    WorkspacePullRequestState state,
    WorkspaceReviewAction action,
  ) async {
    final scope = widget.scope;
    final controller = ref.read(
      workspacePullRequestControllerProvider(scope).notifier,
    );
    final review = state.review!;
    final expected = reviewActionFingerprint(state);
    await _safe(() async {
      switch (action) {
        case .resolve:
          await dispatchPullRequestConflicts(
            context: context,
            ref: ref,
            workspaceId: scope.workspaceId,
            review: review,
          );
        case .fix:
          await dispatchPullRequestFailedChecks(
            context: context,
            ref: ref,
            workspaceId: scope.workspaceId,
            review: review,
          );
        case .ready:
          if (await confirmPullRequestDraftStatus(
            context,
            review: review,
            draft: false,
          )) {
            await controller.setReviewDraft(
              false,
              expectedFingerprint: expected,
            );
          }
        case .merge:
          final method = await showDialog<ReviewMergeMethod>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Merge Method'),
              children: [
                for (final method in state.mergeMethods)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, method),
                    child: Text(method.label),
                  ),
              ],
            ),
          );
          if (method != null &&
              mounted &&
              await confirmPullRequestMerge(
                context,
                review: review,
                stack: state.stack,
                method: method,
              )) {
            await controller.mergeReview(method, expectedFingerprint: expected);
          }
      }
    });
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      showErrorToast(error: error, stackTrace: stackTrace);
    }
  }
}

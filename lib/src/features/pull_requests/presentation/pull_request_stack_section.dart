import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:flutter/material.dart';

class const PullRequestStackSection({
  super.key,
  required final HostedReviewStack? stack,
  required final int currentReviewNumber,
  required final bool canManage,
  required final bool enabled,
  required final bool managing,
  required final bool canCreateFromWorkspaces,
  required final bool creatingFromWorkspaces,
  required final Set<String> localWorkspaceBranches,
  required final Future<void> Function(String url) onOpenUrl,
  required final Future<void> Function(String branch)? onOpenWorkspaceBranch,
  required final VoidCallback onManage,
  required final VoidCallback onCreateFromWorkspaces,
  final String? errorMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStack = stack;
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.gitGraph,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  currentStack == null
                      ? 'Stacked Pull Requests'
                      : 'Stack #${currentStack.number}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
              ),
              if (currentStack != null)
                Text(
                  _positionLabel(currentStack),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          if (currentStack == null)
            Text(
              'This pull request is not part of a native GitHub stack.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            )
          else ...<Widget>[
            Text(
              'Base: ${currentStack.baseBranch.isEmpty ? 'repository default' : currentStack.baseBranch}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            for (final entry in currentStack.entries) ...<Widget>[
              _StackEntryRow(
                entry: entry,
                current: entry.review.number == currentReviewNumber,
                hasLocalWorkspace:
                    entry.review.headBranch != null &&
                    localWorkspaceBranches.contains(entry.review.headBranch),
                onOpenUrl: onOpenUrl,
                onOpenWorkspaceBranch: onOpenWorkspaceBranch,
              ),
              if (entry != currentStack.entries.last)
                const SizedBox(height: AleraTokens.space4),
            ],
          ],
          if (errorMessage != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Text(
              errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ],
          if (canManage) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                if (canCreateFromWorkspaces)
                  OutlinedButton.icon(
                    onPressed: enabled && !managing && !creatingFromWorkspaces
                        ? onCreateFromWorkspaces
                        : null,
                    icon: creatingFromWorkspaces
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AleraIcons.gitBranch, size: 16),
                    label: Text(
                      currentStack == null
                          ? 'Create From Workspaces'
                          : 'Add Workspaces',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: enabled && !managing && !creatingFromWorkspaces
                      ? onManage
                      : null,
                  icon: managing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AleraIcons.link, size: 16),
                  label: Text(
                    currentStack == null
                        ? 'Link Existing Pull Requests'
                        : 'Add Pull Requests',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _positionLabel(HostedReviewStack stack) {
    final position = stack.positionForReview(currentReviewNumber);
    if (position == null) {
      return '${stack.entries.length} pull requests';
    }
    return '$position of ${stack.entries.length}';
  }
}

class const _StackEntryRow({
  required final HostedReviewStackEntry entry,
  required final bool current,
  required final bool hasLocalWorkspace,
  required final Future<void> Function(String url) onOpenUrl,
  required final Future<void> Function(String branch)? onOpenWorkspaceBranch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = entry.review;
    final details = <String>[
      if (review.headBranch != null) review.headBranch!,
      if (review.baseBranch != null) 'Base ${review.baseBranch}',
    ].join(' · ');
    return Material(
      color: current ? AleraTokens.accentSubtle : Colors.transparent,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: InkWell(
        borderRadius: .circular(AleraTokens.radiusSm),
        onTap: review.url.isEmpty
            ? null
            : () => unawaited(onOpenUrl(review.url)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space2),
                child: Icon(
                  _stateIcon(review.state),
                  size: 14,
                  color: _stateColor(review.state),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      '#${review.number} ${review.title}',
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: current ? FontWeight.w600 : null,
                      ),
                    ),
                    if (details.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AleraTokens.space2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (current) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                Text(
                  'Current',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.accent,
                  ),
                ),
              ] else if (hasLocalWorkspace &&
                  onOpenWorkspaceBranch != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Open Workspace',
                  icon: AleraIcons.folderOpen,
                  onPressed: () {
                    final branch = review.headBranch;
                    if (branch != null) {
                      unawaited(onOpenWorkspaceBranch!(branch));
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _stateIcon(HostedReviewState state) => switch (state) {
    HostedReviewState.open => AleraIcons.gitPullRequest,
    HostedReviewState.draft => AleraIcons.edit,
    HostedReviewState.merged => AleraIcons.gitMerge,
    HostedReviewState.closed => AleraIcons.gitPullRequestClosed,
  };

  Color _stateColor(HostedReviewState state) => switch (state) {
    HostedReviewState.open => AleraTokens.success,
    HostedReviewState.draft => AleraTokens.foregroundMuted,
    HostedReviewState.merged => AleraTokens.accent,
    HostedReviewState.closed => AleraTokens.error,
  };
}

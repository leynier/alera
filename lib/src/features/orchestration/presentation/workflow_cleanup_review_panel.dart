import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:flutter/material.dart';

class WorkflowCleanupReviewPanel extends StatefulWidget {
  const WorkflowCleanupReviewPanel({
    super.key,
    required this.status,
    required this.now,
    required this.onBack,
    required this.onRefresh,
    required this.onApply,
    required this.onOpenWorkspace,
    this.busy = false,
    this.error,
  });
  final WorkflowCleanupStatus status;
  final DateTime now;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onApply;
  final ValueChanged<String> onOpenWorkspace;
  final bool busy;
  final Object? error;
  @override
  State<WorkflowCleanupReviewPanel> createState() =>
      _WorkflowCleanupReviewPanelState();
}

class _WorkflowCleanupReviewPanelState
    extends State<WorkflowCleanupReviewPanel> {
  bool _confirmed = false;
  @override
  void didUpdateWidget(WorkflowCleanupReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.preview.id != widget.status.preview.id ||
        oldWidget.status.preview.digest != widget.status.preview.digest) {
      _confirmed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final preview = status.preview;
    final fresh = status.state == WorkflowCleanupState.preview;
    final completed = status.state == WorkflowCleanupState.retired;
    final retry = status.state == WorkflowCleanupState.attention;
    final expired = !widget.now.isBefore(preview.expiresAt);
    final canApply =
        !widget.busy &&
        !completed &&
        (!fresh || (_confirmed && preview.canConfirm(widget.now)));
    final heading = switch (status.state) {
      WorkflowCleanupState.preview => 'Review Cleanup',
      WorkflowCleanupState.applying => 'Cleanup In Progress',
      WorkflowCleanupState.attention => 'Cleanup Needs Attention',
      WorkflowCleanupState.retired => 'Cleanup Complete',
    };
    return FocusTraversalGroup(
      child: ListView.builder(
        padding: const EdgeInsets.all(AleraTokens.space16),
        itemCount: preview.items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: widget.busy ? null : widget.onBack,
                  child: const Text('Back To Resources'),
                ),
                Text(heading, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AleraTokens.space12),
                Text(
                  completed
                      ? 'The selected workspaces were retired. Run history and result evidence remain available.'
                      : 'Cleanup removes the selected worktrees and their tabs. Only branches explicitly marked below will be deleted. Run history and result evidence are retained.',
                ),
                const SizedBox(height: AleraTokens.space12),
                Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: [
                    AleraBadge(
                      label:
                          '${status.retiredWorkspaceIds.length}/${preview.items.length} Retired',
                    ),
                    AleraBadge(
                      label:
                          '${preview.items.where((item) => item.removeBranch).length} Branches To Delete',
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space12),
                Text(
                  'Confirmation',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SelectableText(preview.id, style: AleraTokens.monoCompactStyle),
                if (fresh && expired)
                  const Text(
                    'This preview expired. Return to resources and prepare a new preview.',
                  ),
                if (fresh && preview.items.any((item) => item.blocked))
                  const Text(
                    'Some worktrees are dirty, locked or in a Git operation. Inspect them before preparing a new preview.',
                  ),
                if (retry)
                  const Text(
                    'Resolve the reported issue, then retry this same selection. Active processes will not be stopped for you.',
                  ),
                if (status.state == WorkflowCleanupState.applying)
                  const Text(
                    'This selection is already confirmed. Refresh its status, or continue the same operation if its response was interrupted.',
                  ),
                if (status.error != null)
                  SelectableText(
                    status.error!,
                    style: TextStyle(color: AleraTokens.error),
                  ),
                if (widget.error != null)
                  SelectableText(
                    widget.error.toString(),
                    style: TextStyle(color: AleraTokens.error),
                  ),
                const SizedBox(height: AleraTokens.space16),
              ],
            );
          }
          if (index == preview.items.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fresh)
                    MergeSemantics(
                      child: Row(
                        children: [
                          AleraCheckbox(
                            value: _confirmed,
                            enabled:
                                !widget.busy && preview.canConfirm(widget.now),
                            onChanged: (value) =>
                                setState(() => _confirmed = value),
                          ),
                          const SizedBox(width: AleraTokens.space8),
                          const Expanded(child: Text('Confirm Selection')),
                        ],
                      ),
                    ),
                  const SizedBox(height: AleraTokens.space8),
                  Wrap(
                    spacing: AleraTokens.space8,
                    runSpacing: AleraTokens.space8,
                    children: [
                      TextButton(
                        onPressed: widget.busy ? null : widget.onRefresh,
                        child: const Text('Refresh Status'),
                      ),
                      if (!completed)
                        FilledButton(
                          onPressed: canApply
                              ? () => widget.onApply(retry)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AleraTokens.error,
                            foregroundColor: AleraTokens.onError,
                          ),
                          child: Text(
                            widget.busy
                                ? 'Cleaning...'
                                : fresh
                                ? 'Clean Selected Resources'
                                : retry
                                ? 'Retry Cleanup'
                                : 'Continue Cleanup',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }
          final item = preview.items[index - 1];
          final retired = status.retiredWorkspaceIds.contains(item.identity.id);
          return Padding(
            key: ValueKey(item.identity.id),
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.identity.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  item.identity.taskId == null
                      ? 'Integration Workspace'
                      : 'Task Attempt ${item.identity.attempt}',
                ),
                const SizedBox(height: AleraTokens.space8),
                SelectableText(
                  item.identity.path,
                  style: AleraTokens.monoCompactStyle,
                ),
                Text(
                  retired
                      ? 'Retired'
                      : item.removeBranch
                      ? 'Delete Branch'
                      : 'Keep Branch',
                ),
                SelectableText(
                  item.identity.branch,
                  style: AleraTokens.monoCompactStyle,
                ),
                Text(
                  'Reviewed HEAD',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                SelectableText(
                  item.headSha,
                  style: AleraTokens.monoCompactStyle,
                ),
                Text(
                  'Base SHA',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                SelectableText(
                  item.identity.baseSha,
                  style: AleraTokens.monoCompactStyle,
                ),
                if (item.locked) const Text('Worktree is locked.'),
                if (item.operationInProgress)
                  const Text('A Git operation is in progress.'),
                if (item.dirty) ...[
                  const Text(
                    'Uncommitted, untracked or ignored files are present.',
                  ),
                  for (final path in item.changedPaths.take(8))
                    SelectableText(path, style: AleraTokens.monoCompactStyle),
                  if (item.pathsTruncated || item.changedPaths.length > 8)
                    const Text(
                      'More changed paths exist. Open the workspace to inspect all changes.',
                    ),
                ],
                if (!retired)
                  TextButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onOpenWorkspace(item.identity.id),
                    child: const Text('Open Workspace'),
                  ),
                const Divider(color: AleraTokens.borderSubtle),
              ],
            ),
          );
        },
      ),
    );
  }
}

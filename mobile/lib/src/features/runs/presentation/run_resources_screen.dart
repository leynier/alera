import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_cleanup.dart';
import 'package:alera_mobile/src/features/runs/domain/run_cleanup_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Worktrees and branches an isolated run kept, and the reviewed cleanup that
/// removes them: select, preview, confirm, apply.
class const RunResourcesScreen({
  super.key,
  required final String hostId,
  required final String runId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourcesProvider = mobileRunResourcesProvider(hostId, runId);
    final resources = ref.watch(resourcesProvider);
    final draft = ref.watch(mobileRunCleanupProvider(hostId, runId));
    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      body: SafeArea(
        child: switch (resources) {
          AsyncValue(value: final RunResourcesSnapshot snapshot) =>
            RefreshIndicator(
              onRefresh: () => ref.refresh(resourcesProvider.future),
              child: ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  if (draft.status case final status?)
                    ..._statusView(context, ref, status)
                  else if (draft.preview case final preview?)
                    ..._previewView(context, ref, preview, draft.busy)
                  else
                    ..._selectionView(context, ref, snapshot, draft),
                  ..._history(context, ref, snapshot.history, draft.busy),
                ],
              ),
            ),
          AsyncValue(hasError: true, :final error) => AleraEmptyState(
            icon: AleraIcons.loadFailed,
            title: 'Resources Unavailable',
            message: runErrorMessage(error!),
            action: TextButton(
              onPressed: () => ref.invalidate(resourcesProvider),
              child: const Text('Retry'),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  MobileRunCleanup _cleanup(WidgetRef ref) =>
      ref.read(mobileRunCleanupProvider(hostId, runId).notifier);

  List<Widget> _selectionView(
    BuildContext context,
    WidgetRef ref,
    RunResourcesSnapshot snapshot,
    RunCleanupDraft draft,
  ) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final selectable = snapshot.resources.where((item) => item.selectable);
    return <Widget>[
      Text(
        'Retained worktrees and branches stay until you clean up. Selecting removes nothing until you confirm a preview.',
        style: muted,
      ),
      if (snapshot.resources.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AleraTokens.space16),
          child: Text('This run kept no worktrees.', textAlign: .center),
        )
      else ...<Widget>[
        Wrap(
          children: <Widget>[
            TextButton(
              onPressed: selectable.isEmpty
                  ? null
                  : () => _cleanup(ref).selectAll(snapshot.resources),
              child: const Text('Select All'),
            ),
            TextButton(
              onPressed: draft.selected.isEmpty
                  ? null
                  : _cleanup(ref).clearSelection,
              child: const Text('Clear Selection'),
            ),
          ],
        ),
        for (final resource in snapshot.resources) ...<Widget>[
          CheckboxListTile(
            key: ValueKey<String>('run-resource-${resource.workspaceId}'),
            contentPadding: EdgeInsets.zero,
            value: draft.isSelected(resource.workspaceId),
            onChanged: resource.selectable && !draft.busy
                ? (value) =>
                      _cleanup(ref)
                          .toggle(resource.workspaceId, selected: value == true)
                : null,
            title: Text(resource.name),
            subtitle: Text(
              <String>[
                ?resource.branch,
                if (resource.attempt > 0) 'Attempt ${resource.attempt}',
                if (resource.retired) 'Removed',
                if (resource.cleanupState case final state?
                    when !resource.retired)
                  'Cleanup $state',
              ].join(' · '),
              style: muted,
            ),
          ),
          if (draft.isSelected(resource.workspaceId) && resource.branch != null)
            SwitchListTile(
              key: ValueKey<String>(
                'run-resource-branch-${resource.workspaceId}',
              ),
              contentPadding: const EdgeInsets.only(left: AleraTokens.space32),
              value: draft.removesBranch(resource.workspaceId),
              onChanged: draft.busy
                  ? null
                  : (value) => _cleanup(ref)
                        .setRemoveBranch(resource.workspaceId, remove: value),
              title: const Text('Also Delete This Branch'),
            ),
        ],
        const SizedBox(height: AleraTokens.space8),
        FilledButton(
          onPressed: draft.selected.isEmpty || draft.busy
              ? null
              : () => unawaited(_guard(context, _cleanup(ref).preview)),
          child: const Text('Preview'),
        ),
      ],
    ];
  }

  List<Widget> _previewView(
    BuildContext context,
    WidgetRef ref,
    RunCleanupPreview preview,
    bool busy,
  ) {
    final theme = Theme.of(context);
    return <Widget>[
      const AleraSectionHeader(label: 'Preview'),
      for (final item in preview.items)
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(item.name, style: theme.textTheme.titleSmall),
                Text(
                  item.removeBranch
                      ? 'Removes the worktree and branch ${item.branch ?? ''}'
                            .trim()
                      : 'Removes the worktree and keeps branch ${item.branch ?? ''}'
                            .trim(),
                  style: theme.textTheme.bodySmall,
                ),
                if (item.dirty)
                  _risk(context, 'Uncommitted changes will be lost.'),
                if (item.operationInProgress)
                  _risk(context, 'A Git operation is in progress.'),
                if (item.locked) _risk(context, 'The worktree is locked.'),
                if (item.changedPaths.isNotEmpty)
                  Text(
                    item.changedPaths.join('\n') +
                        (item.pathsTruncated ? '\n…' : ''),
                    style: AleraTokens.monoStyle,
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: AleraTokens.space8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          TextButton(
            onPressed: busy ? null : _cleanup(ref).backToResources,
            child: const Text('Back To Resources'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
            ),
            onPressed: busy
                ? null
                : () => unawaited(_apply(context, ref, preview)),
            child: const Text('Apply Cleanup'),
          ),
        ],
      ),
    ];
  }

  Widget _risk(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.warning),
  );

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    RunCleanupPreview preview,
  ) async {
    final cleanup = _cleanup(ref);
    final count = preview.items.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Apply Cleanup',
        message:
            'Remove ${count == 1 ? 'this worktree' : 'these $count worktrees'} as previewed. This cannot be undone.',
        confirmLabel: 'Apply Cleanup',
        destructive: true,
      ),
    );
    if (!context.mounted) return;
    await _guard(context, () => cleanup.apply(confirmed: confirmed == true));
  }

  List<Widget> _statusView(
    BuildContext context,
    WidgetRef ref,
    RunCleanupStatus status,
  ) => <Widget>[
    const AleraSectionHeader(label: 'Cleanup'),
    Row(
      children: <Widget>[
        AleraBadge(
          label: _stateLabel(status.state.name),
          tone: status.state == RunCleanupState.attention
              ? AleraBadgeTone.attention
              : status.state == RunCleanupState.retired
              ? AleraBadgeTone.success
              : AleraBadgeTone.neutral,
        ),
        const SizedBox(width: AleraTokens.space8),
        Text(
          '${status.retiredWorkspaceIds.length}/${status.preview.items.length} removed',
        ),
      ],
    ),
    if (status.error case final error?)
      Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space8),
        child: AleraNotice(icon: AleraIcons.warning, message: error),
      ),
    const SizedBox(height: AleraTokens.space8),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _cleanup(ref).clearSelection,
        child: const Text('Back To Resources'),
      ),
    ),
  ];

  List<Widget> _history(
    BuildContext context,
    WidgetRef ref,
    List<RunCleanupHistoryEntry> history,
    bool busy,
  ) {
    if (history.isEmpty) return const <Widget>[];
    return <Widget>[
      const AleraSectionHeader(label: 'History'),
      for (final entry in history)
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AleraBadge(
                      label: _stateLabel(entry.state),
                      tone: entry.state == 'attention'
                          ? AleraBadgeTone.attention
                          : AleraBadgeTone.neutral,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Text(
                      '${entry.retiredCount}/${entry.resourceCount} removed',
                    ),
                  ],
                ),
                if (entry.error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: AleraTokens.space4),
                    child: Text(error),
                  ),
                if (entry.state == 'attention')
                  Wrap(
                    children: <Widget>[
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                _guard(
                                  context,
                                  () => _cleanup(ref).retry(entry.id),
                                ),
                              ),
                        child: const Text('Retry Cleanup'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(_abandon(context, ref, entry.id)),
                        child: const Text('Abandon Cleanup'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  Future<void> _abandon(
    BuildContext context,
    WidgetRef ref,
    String cleanupId,
  ) async {
    final cleanup = _cleanup(ref);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Abandon Cleanup',
        message: 'Stop this cleanup and release its worktrees. Anything already removed stays removed.',
        confirmLabel: 'Abandon Cleanup',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(context, () => cleanup.abandon(cleanupId));
  }

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(runErrorMessage(error))));
    }
  }
}

String _stateLabel(String state) => switch (state) {
  'preview' => 'Previewed',
  'applying' => 'Applying',
  'retired' => 'Removed',
  'attention' => 'Needs Attention',
  'abandoned' => 'Abandoned',
  _ => state,
};

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/orchestration/application/workflow_cleanup_session.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:flutter/material.dart';

class WorkflowCleanupSelectionPanel extends StatelessWidget {
  const WorkflowCleanupSelectionPanel({
    super.key,
    required this.session,
    required this.allowPrepare,
    required this.onBack,
    required this.onOpen,
    required this.onWorkspace,
  });
  final WorkflowCleanupSession session;
  final bool allowPrepare;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onWorkspace;

  @override
  Widget build(BuildContext context) {
    final selection = session.selection;
    final rows = <Object>[
      'header',
      ...session.resources,
      'resources-end',
      'history',
      ...session.history,
      'history-end',
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(AleraTokens.space16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final item = rows[index];
        if (item is WorkflowCleanupResource) {
          final identity = item.identity;
          final selected = selection.containsKey(identity.id);
          return Padding(
            key: ValueKey('resource:${identity.id}'),
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identity.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  identity.taskId == null
                      ? 'Integration Workspace'
                      : 'Task Attempt ${identity.attempt}',
                ),
                SelectableText(
                  identity.path,
                  style: AleraTokens.monoCompactStyle,
                ),
                SelectableText(
                  identity.branch,
                  style: AleraTokens.monoCompactStyle,
                ),
                if (item.retired)
                  const Text('Retired. History is preserved.')
                else if (!item.registered)
                  const Text(
                    'Workspace registration is unavailable. Inspect its retained history.',
                  )
                else if (item.cleanupId != null)
                  const Text(
                    'This resource belongs to an existing cleanup. Open its status below.',
                  )
                else if (!item.canSelect)
                  const Text(
                    'This resource has not finished preparation. Reconcile it before cleanup.',
                  ),
                if (item.canSelect)
                  _CleanupToggle(
                    label: 'Select Resource',
                    value: selected,
                    enabled:
                        allowPrepare &&
                        !session.selectionLocked &&
                        (selected || selection.length < 25),
                    onChanged: (value) => session.select(identity.id, value),
                  ),
                if (selected)
                  _CleanupToggle(
                    label: 'Also Delete This Branch',
                    value: selection[identity.id]!,
                    enabled: !session.selectionLocked,
                    onChanged: (value) =>
                        session.removeBranch(identity.id, value),
                  ),
                Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: [
                    if (item.registered && !item.retired)
                      TextButton(
                        onPressed: session.busy
                            ? null
                            : () => onWorkspace(identity.id),
                        child: const Text('Open Workspace'),
                      ),
                    if (item.cleanupId != null)
                      TextButton(
                        onPressed: session.busy
                            ? null
                            : () => onOpen(item.cleanupId!),
                        child: const Text('Open Cleanup'),
                      ),
                  ],
                ),
                const Divider(color: AleraTokens.borderSubtle),
              ],
            ),
          );
        }
        if (item is WorkflowCleanupSummary) {
          return AleraActivityRow(
            key: ValueKey('cleanup:${item.id}'),
            title: 'Cleanup ${item.id.split('-').first}',
            subtitle:
                '${_cleanupLabel(item.state)} (${item.retiredCount}/${item.resourceCount} retired)${item.error == null ? '' : '\n${item.error}'}',
            metadata: item.id,
            statusColor: item.state == WorkflowCleanupState.attention
                ? AleraTokens.warning
                : AleraTokens.foregroundMuted,
            onPressed: () {
              if (!session.busy) onOpen(item.id);
            },
          );
        }
        return switch (item) {
          'header' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                onPressed: session.busy ? null : onBack,
                child: const Text('Back To Run'),
              ),
              Text(
                'Workflow Resources',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AleraTokens.space12),
              const Text(
                'Resources are retained after success, cancellation or errors. Select up to 25 worktrees to inspect a cleanup preview. Branches are kept unless you explicitly select their deletion.',
              ),
              if (!allowPrepare)
                const Text(
                  'Finish or cancel this run before preparing a cleanup.',
                ),
              if (session.loading) const Text('Loading resources...'),
              if (session.error != null)
                SelectableText(
                  session.error.toString(),
                  style: const TextStyle(color: AleraTokens.error),
                ),
              Wrap(
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: [
                  TextButton(
                    onPressed: session.busy ? null : session.refresh,
                    child: const Text('Refresh Resources'),
                  ),
                  if (selection.isNotEmpty || session.previewPending)
                    TextButton(
                      onPressed: session.busy ? null : session.clearSelection,
                      child: const Text('Clear Selection'),
                    ),
                  FilledButton(
                    onPressed: allowPrepare && session.canPrepare
                        ? session.prepare
                        : null,
                    child: Text(
                      session.busy
                          ? 'Working...'
                          : session.previewPending
                          ? 'Retry Preview'
                          : 'Review Cleanup',
                    ),
                  ),
                ],
              ),
              Text('${selection.length}/25 resources selected'),
              if (!session.loading && session.resources.isEmpty)
                const Text('This run has no retained workflow resources.'),
            ],
          ),
          'resources-end' =>
            session.resourceCursor == null
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: session.busy
                        ? null
                        : () => session.loadMore(operations: false),
                    child: const Text('Load More Resources'),
                  ),
          'history' => Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cleanup History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!session.loading && session.history.isEmpty)
                  const Text(
                    'No cleanup previews have been created for this run.',
                  ),
              ],
            ),
          ),
          'history-end' =>
            session.historyCursor == null
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: session.busy
                        ? null
                        : () => session.loadMore(operations: true),
                    child: const Text('Load More Cleanups'),
                  ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

String _cleanupLabel(WorkflowCleanupState state) => switch (state) {
  WorkflowCleanupState.preview => 'Preview',
  WorkflowCleanupState.applying => 'Applying',
  WorkflowCleanupState.attention => 'Attention',
  WorkflowCleanupState.retired => 'Retired',
  WorkflowCleanupState.abandoned => 'Abandoned',
};

class _CleanupToggle extends StatelessWidget {
  const _CleanupToggle({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        AleraCheckbox(value: value, enabled: enabled, onChanged: onChanged),
        const SizedBox(width: AleraTokens.space8),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

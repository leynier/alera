import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/runs/application/run_cleanup_session.dart';
import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:flutter/material.dart';

/// The retained worktrees and branches of a run, a selection of at most 25
/// for a cleanup preview, and the cleanup history.
class const RunResourcesSelection({
  super.key,
  required final RunCleanupSession session,
  required final bool allowPrepare,
  required final ValueChanged<String> onOpen,
  required final ValueChanged<String> onWorkspace,
  required final ValueChanged<String> onRetry,
  required final ValueChanged<String> onAbandon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
      itemBuilder: (context, index) => switch (rows[index]) {
        final RunCleanupResource item => _ResourceRow(
          key: ValueKey<String>('resource:${item.identity.id}'),
          item: item,
          session: session,
          allowPrepare: allowPrepare,
          onWorkspace: onWorkspace,
          onOpen: onOpen,
        ),
        final RunCleanupHistoryItem item => _HistoryRow(
          key: ValueKey<String>('cleanup:${item.id}'),
          item: item,
          busy: session.busy,
          onOpen: onOpen,
          onRetry: onRetry,
          onAbandon: onAbandon,
        ),
        'header' => _header(context),
        'resources-end' => Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space8,
            children: <Widget>[
              if (session.resourceCursor != null)
                TextButton(
                  onPressed: session.busy
                      ? null
                      : () => session.loadMore(operations: false),
                  child: const Text('Load More Resources'),
                ),
              FilledButton(
                key: const ValueKey<String>('runCleanupPreview'),
                onPressed: allowPrepare && session.canPrepare
                    ? session.prepare
                    : null,
                child: Text(
                  session.busy
                      ? 'Preparing…'
                      : session.previewPending
                      ? 'Retry Preview'
                      : 'Preview',
                ),
              ),
            ],
          ),
        ),
        'history' => AleraSectionHeader(
          label: 'Cleanup History',
          padding: const EdgeInsets.only(
            top: AleraTokens.space16,
            bottom: AleraTokens.space4,
          ),
          trailing: !session.loading && session.history.isEmpty
              ? Text(
                  'No cleanups yet',
                  style: Theme.of(context).textTheme.labelSmall,
                )
              : null,
        ),
        'history-end' =>
          session.historyCursor == null
              ? const SizedBox.shrink()
              : TextButton(
                  onPressed: session.busy
                      ? null
                      : () => session.loadMore(operations: true),
                  child: const Text('Load More History'),
                ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _header(BuildContext context) {
    final selection = session.selection;
    final selectable = session.resources.where((item) => item.canSelect);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: <Widget>[
        Text(
          'Retained worktrees and branches stay until you clean up. Selecting removes nothing until you confirm a preview.',
          style: muted,
        ),
        if (!allowPrepare)
          Text('Finish or cancel this run before cleaning up.', style: muted),
        if (session.error != null)
          AleraInlineNotice(
            tone: .error,
            message: runErrorMessage(session.error!),
          ),
        if (session.loading) Text('Loading resources…', style: muted),
        if (!session.loading && session.resources.isEmpty)
          Text('This run retained no worktrees or branches.', style: muted),
        if (selectable.isNotEmpty)
          Wrap(
            spacing: AleraTokens.space12,
            runSpacing: AleraTokens.space8,
            crossAxisAlignment: .center,
            children: <Widget>[
              AleraCheckbox(
                key: const ValueKey<String>('runCleanupSelectAll'),
                label: 'Select All',
                value:
                    selection.length ==
                        selectable.length.clamp(0, runCleanupSelectionLimit) &&
                    selection.isNotEmpty,
                enabled: allowPrepare && !session.selectionLocked,
                onChanged: (value) =>
                    value ? session.selectAll() : session.clearSelection(),
              ),
              Text(
                '${selection.length}/$runCleanupSelectionLimit selected',
                key: const ValueKey<String>('runCleanupSelectionCount'),
                style: muted,
              ),
              if (selection.isNotEmpty || session.previewPending)
                TextButton(
                  onPressed: session.busy ? null : session.clearSelection,
                  child: const Text('Clear Selection'),
                ),
            ],
          ),
      ],
    );
  }
}

class const _ResourceRow({
  super.key,
  required final RunCleanupResource item,
  required final RunCleanupSession session,
  required final bool allowPrepare,
  required final ValueChanged<String> onWorkspace,
  required final ValueChanged<String> onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final identity = item.identity;
    final selection = session.selection;
    final selected = selection.containsKey(identity.id);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final note = item.retired
        ? 'Retired · history is preserved'
        : !item.registered
        ? 'Registration unavailable'
        : item.cleanupId != null
        ? 'Part of an existing cleanup'
        : !item.canSelect
        ? 'Locked · ${item.phase}'
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space4,
        children: <Widget>[
          Row(
            crossAxisAlignment: .start,
            spacing: AleraTokens.space8,
            children: <Widget>[
              AleraCheckbox(
                key: ValueKey<String>('runCleanupSelect:${identity.id}'),
                value: selected,
                enabled:
                    item.canSelect &&
                    allowPrepare &&
                    !session.selectionLocked &&
                    (selected || selection.length < runCleanupSelectionLimit),
                onChanged: (value) => session.select(identity.id, value),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    Text(
                      identity.taskId == null
                          ? '${identity.name} · Integration'
                          : '${identity.name} · Attempt ${identity.attempt}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SelectableText(
                      identity.path,
                      style: AleraTokens.monoCompactStyle,
                    ),
                    SelectableText(
                      identity.branch,
                      style: AleraTokens.monoCompactStyle,
                    ),
                    if (note != null) Text(note, style: muted),
                  ],
                ),
              ),
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
          if (selected)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AleraTokens.space24,
              ),
              child: AleraCheckbox(
                key: ValueKey<String>('runCleanupBranch:${identity.id}'),
                label: 'Also Delete This Branch',
                value: selection[identity.id]!,
                enabled: !session.selectionLocked,
                onChanged: (value) => session.removeBranch(identity.id, value),
              ),
            ),
        ],
      ),
    );
  }
}

class const _HistoryRow({
  super.key,
  required final RunCleanupHistoryItem item,
  required final bool busy,
  required final ValueChanged<String> onOpen,
  required final ValueChanged<String> onRetry,
  required final ValueChanged<String> onAbandon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (label, tone) = runCleanupStateLabel(item.state);
    final attention = item.state == RunCleanupState.attention;
    return InkWell(
      onTap: busy ? null : () => onOpen(item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
        child: Row(
          spacing: AleraTokens.space8,
          children: <Widget>[
            AleraBadge(label: label, tone: tone),
            Expanded(
              child: Text(
                '${item.resourceCount} ${item.resourceCount == 1 ? 'resource' : 'resources'} · ${item.retiredCount} retired${item.error == null ? '' : ' · ${item.error}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (attention) ...<Widget>[
              TextButton(
                onPressed: busy ? null : () => onRetry(item.id),
                child: const Text('Retry Cleanup'),
              ),
              TextButton(
                onPressed: busy ? null : () => onAbandon(item.id),
                child: const Text('Abandon Cleanup'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

(String, AleraBadgeTone) runCleanupStateLabel(RunCleanupState state) =>
    switch (state) {
      RunCleanupState.preview => ('Preview', AleraBadgeTone.neutral),
      RunCleanupState.applying => ('Applying', AleraBadgeTone.info),
      RunCleanupState.attention => ('Attention', AleraBadgeTone.attention),
      RunCleanupState.retired => ('Applied', AleraBadgeTone.success),
      RunCleanupState.abandoned => ('Abandoned', AleraBadgeTone.neutral),
    };
